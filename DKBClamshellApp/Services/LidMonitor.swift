import AppKit
import DKBClamshellCore
import QuartzCore

/// Wires the pieces together (plan §5.2): polls the sensor on a background
/// timer, feeds `LidMotionTracker` and `FoldStateMachine`, and drives the
/// chosen renderer from a display link while the overlay is visible.
@MainActor
final class LidMonitor {
    enum Status: Equatable {
        case notStarted
        case running
        case unsupported(String)
        case sensorError(String)
    }

    private let preferences: AppPreferences
    private(set) var status: Status = .notStarted
    private(set) var machine: FoldStateMachine
    private var tracker = LidMotionTracker()
    private var reader: HIDLidAngleReader?
    private var pollTimer: DispatchSourceTimer?
    private var displayLink: CADisplayLink?

    private var overlay: OverlayWindow?
    private var renderer: EffectRendering?
    private var rendererIsFull = false
    private var hud: DebugHUDWindow?
    private var frameCount = 0
    private var fpsWindowStart: TimeInterval = 0
    private var fps = 0

    /// Settings' Preview slider (plan D17): while set, this angle replaces the
    /// sensor so the whole pipeline — tracker, state machine, capture,
    /// renderer — runs exactly as it would for a real lid.
    var previewAngle: Double? {
        didSet { if previewAngle != nil, oldValue == nil { schedulePoll(after: 0) } }
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        machine = FoldStateMachine(endAngle: Double(preferences.endAngle))
    }

    func start() {
        guard status == .notStarted else { return }
        do {
            reader = try HIDLidAngleReader()
        } catch LidSensorError.notFound {
            let why: String
            switch LidHardware.support() {
            case .unsupported(let reason): why = reason
            case .supported, .unknown: why = "macOS does not expose a lid angle sensor on this Mac."
            }
            status = .unsupported(why)
            return
        } catch {
            status = .sensorError("\(error)")
            return
        }
        status = .running
        observeSystem()
        schedulePoll(after: 0)
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--preview-angle"), i + 1 < CommandLine.arguments.count {
            previewAngle = Double(CommandLine.arguments[i + 1])
        }
        // `--preview-hold N`: rest at 110°, then close to N° and hold — for screenshots.
        if let i = CommandLine.arguments.firstIndex(of: "--preview-hold"), i + 1 < CommandLine.arguments.count,
           let hold = Double(CommandLine.arguments[i + 1]) {
            previewAngle = 110
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.previewAngle = hold }
        }
        // `--preview-sweep`: a synthetic close, 110° → 20° in 10 Hz steps like the
        // sensor, to measure frame rate and transitions without touching the lid.
        if CommandLine.arguments.contains("--preview-sweep") {
            previewAngle = 110
            var angle = 110.0
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                let done = MainActor.assumeIsolated { () -> Bool in
                    guard let self else { return true }
                    if angle > 20 { angle -= 10; self.previewAngle = angle; return false }
                    NSLog("sweep done: %d frames while active", self.frameCount)
                    return true
                }
                if done { timer.invalidate() }
            }
        }
        #endif
    }

    // MARK: Sensor polling

    private func schedulePoll(after interval: TimeInterval) {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.dangkhoabach.dkb-clamshell.lid", qos: .userInteractive))
        timer.schedule(deadline: .now() + interval, repeating: LidMotionTracker.pollInterval)
        let reader = self.reader
        // `@Sendable`: without it the closure inherits this method's main-actor
        // isolation and Swift traps when the timer fires on its own queue.
        timer.setEventHandler { @Sendable [weak self] in
            let time = CACurrentMediaTime()
            Task { @MainActor [weak self] in
                guard let self else { return }
                let angle: Double
                if let preview = self.previewAngle {
                    angle = preview
                } else {
                    guard let reader else { return }
                    do { angle = try reader.readAngle() } catch {
                        self.status = .sensorError("\(error)"); self.pollTimer?.cancel(); return
                    }
                }
                self.receive(LidSample(angle: angle, time: time))
            }
        }
        timer.resume()
        pollTimer = timer
    }

    private func receive(_ sample: LidSample) {
        tracker.add(sample)
        guard preferences.isEnabled else { return }
        step(at: sample.time)
    }

    // MARK: Per-frame

    private func step(at time: TimeInterval) {
        guard let angle = tracker.displayAngle(at: time) else { return }
        machine.endAngle = Double(preferences.endAngle)
        let before = machine.phase
        machine.update(angle: angle, velocity: tracker.velocity, isMoving: tracker.isMoving, time: time)
        if machine.phase != before { transition(from: before, to: machine.phase) }
        if machine.phase == .active {
            let params = EffectParameters(progress: machine.progress(angle: angle),
                                          delta: (machine.restAngle ?? angle) - angle,
                                          intensity: preferences.intensity, maxDarkness: preferences.maxDarkness)
            renderer?.update(params)
            frameCount += 1
        }
        updateHUD(angle: angle, time: time)
    }

    private func transition(from: FoldPhase, to: FoldPhase) {
        #if DEBUG
        NSLog("phase %@ → %@ (rest %.1f°, start %.1f°)", "\(from)", "\(to)", machine.restAngle ?? -1, machine.startAngle)
        #endif
        switch to {
        case .prewarm:
            ensureOverlay()
            renderer?.prepare()
        case .active:
            ensureOverlay()
            if from == .idle { renderer?.prepare() }
            overlay?.orderFrontRegardless()
            frameCount = 0
            startDisplayLink()
        case .idle:
            stopDisplayLink()
            overlay?.orderOut(nil)
            renderer?.stop()
        case .reveal:
            break   // Phase 4
        }
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        step(at: CACurrentMediaTime())
    }

    private func startDisplayLink() {
        guard displayLink == nil, let screen = BuiltinScreen.screen() else { return }
        let link = screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Overlay & renderer

    private var wantsFull: Bool {
        switch preferences.rendererMode {
        case .lite: return false
        case .full: return true
        case .auto: return CGPreflightScreenCaptureAccess()
        }
    }

    private func ensureOverlay() {
        guard let screen = BuiltinScreen.screen() else { return }
        if overlay == nil { overlay = OverlayWindow(screen: screen) } else { overlay?.fit(to: screen) }
        guard let overlay else { return }
        let full = wantsFull
        if renderer == nil || rendererIsFull != full {
            renderer?.stop()
            let size = screen.frame.size
            if full, let id = BuiltinScreen.displayID(), let r = FullEffectRenderer(size: size, displayID: id) {
                renderer = r; rendererIsFull = true
            } else {
                renderer = LiteEffectRenderer(size: size); rendererIsFull = false
            }
            overlay.contentView = renderer?.view
        }
    }

    // MARK: System events

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let before = self.machine.phase
                    self.machine.screensDidSleep()
                    if before != .idle { self.transition(from: before, to: .idle) }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = BuiltinScreen.screen() else { return }
                self.overlay?.fit(to: screen)
            }
        }
    }

    // MARK: HUD

    private func updateHUD(angle: Double, time: TimeInterval) {
        guard preferences.showDebugHUD else {
            if hud != nil { hud?.orderOut(nil); hud = nil }
            return
        }
        if hud == nil, let screen = BuiltinScreen.screen() { hud = DebugHUDWindow(screen: screen) }
        if time - fpsWindowStart >= 1 { fps = frameCount; frameCount = 0; fpsWindowStart = time }
        let raw = tracker.last?.angle ?? 0
        hud?.show(String(format: "lid %.1f° (raw %.1f°)  v %.0f°/s  rest %.0f°\n%@ · %@ · %d fps%@",
                         angle, raw, tracker.velocity, machine.restAngle ?? 0, "\(machine.phase)", rendererIsFull ? "Full" : "Lite", fps,
                         previewAngle == nil ? "" : " · preview"))
    }
}
