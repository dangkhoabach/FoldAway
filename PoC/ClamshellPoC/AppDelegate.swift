import AppKit
import CoreGraphics

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate(); app.delegate = d
        app.setActivationPolicy(.regular)
        app.run()
    }

    enum Mode: Int { case off, lite, full }

    private var window: NSWindow!
    private let angleLabel = NSTextField(labelWithString: "angle: —")
    private let logView = NSTextView()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let follow = NSButton(checkboxWithTitle: "Follow lid (85° → 25°)", target: nil, action: nil)
    private let modePopup = NSPopUpButton()

    private var sensor: LidSensor?
    private var overlay: OverlayWindow?
    private var lite: LiteView?
    private var full: FullView?
    private let capture = Capture()
    private var mode: Mode = .off
    private var lastAngle = -1
    private var crossed85At: CFAbsoluteTime?
    private var fpsTimer: Timer?
    private var lastDrawCount = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        buildWindow()
        Log.sink = { [weak self] line in
            guard let self else { return }
            self.logView.textStorage?.append(NSAttributedString(string: line + "\n", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]))
            self.logView.scrollToEndOfDocument(nil)
        }
        Log.w("==== launch build=\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?") ====")
        Log.w("0.4 TCC ScreenCapture preflight: \(CGPreflightScreenCaptureAccess())")
        sensor = LidSensor()
        if let a = sensor?.read() { Log.w("0.1 initial angle: \(a)°"); lastAngle = a }
        sensor?.onAngle = { [weak self] a in self?.angleChanged(a) }
        sensor?.start(hz: 120)

        let ws = NSWorkspace.shared.notificationCenter
        for (name, tag) in [(NSWorkspace.willSleepNotification, "willSleep"), (NSWorkspace.screensDidSleepNotification, "screensDidSleep"),
                            (NSWorkspace.didWakeNotification, "didWake"), (NSWorkspace.screensDidWakeNotification, "screensDidWake")] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                var extra = ""
                if tag == "screensDidSleep", let t = self.crossed85At { extra = String(format: "  (%.0f ms after crossing 85°)", (CFAbsoluteTimeGetCurrent() - t) * 1000) }
                Log.w("0.2 \(tag) angle=\(self.sensor?.read() ?? -1)° last=\(self.lastAngle)°\(extra)")
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Log.w("0.2 screenIsLocked angle=\(self?.sensor?.read() ?? -1)°") }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Log.w("0.2 screenIsUnlocked angle=\(self?.sensor?.read() ?? -1)°") }
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Clamshell PoC"; window.center()
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        angleLabel.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        root.addArrangedSubview(angleLabel)

        let row1 = NSStackView(); row1.orientation = .horizontal
        modePopup.addItems(withTitles: ["Overlay: Off", "Overlay: Lite", "Overlay: Full"])
        modePopup.target = self; modePopup.action = #selector(modeChanged)
        row1.addArrangedSubview(modePopup)
        slider.target = self; slider.action = #selector(sliderChanged); slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        row1.addArrangedSubview(NSTextField(labelWithString: "progress")); row1.addArrangedSubview(slider)
        root.addArrangedSubview(row1)

        let row2 = NSStackView(); row2.orientation = .horizontal
        row2.addArrangedSubview(follow)
        let b = NSButton(title: "0.3 Measure SCStream start ×10", target: self, action: #selector(measureStart))
        row2.addArrangedSubview(b)
        let c = NSButton(title: "Clear log", target: self, action: #selector(clearLog))
        row2.addArrangedSubview(c)
        root.addArrangedSubview(row2)

        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = logView
        logView.isEditable = false; logView.autoresizingMask = [.width]
        logView.minSize = NSSize(width: 0, height: 0); logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logView.isVerticallyResizable = true; logView.textContainer?.widthTracksTextView = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: sensor → overlay

    private func angleChanged(_ a: Int) {
        angleLabel.stringValue = "angle: \(a)°"
        Log.w("angle \(a)°")
        if lastAngle > 85, a <= 85 { crossed85At = CFAbsoluteTimeGetCurrent() }
        if a > 95 { crossed85At = nil }
        lastAngle = a
        if follow.state == .on {
            let p = min(1, max(0, (85.0 - Double(a)) / (85.0 - 25.0)))
            slider.doubleValue = p
            apply(progress: p)
        }
    }

    private func apply(progress: Double) {
        let p = EffectParams(progress: progress)
        switch mode {
        case .off: break
        case .lite: lite?.apply(p)
        case .full: full?.params = p; full?.render()
        }
    }

    @objc private func sliderChanged() { apply(progress: slider.doubleValue) }
    @objc private func clearLog() { logView.string = "" }

    @objc private func modeChanged() {
        let new = Mode(rawValue: modePopup.indexOfSelectedItem) ?? .off
        guard new != mode else { return }
        teardownOverlay()
        mode = new
        guard mode != .off else { return }
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == Capture.builtinDisplayID() }) else {
            Log.w("no built-in NSScreen"); mode = .off; modePopup.selectItem(at: 0); return
        }
        let ov = OverlayWindow(screen: screen)
        overlay = ov
        switch mode {
        case .lite:
            let v = LiteView(frame: NSRect(origin: .zero, size: screen.frame.size)); lite = v; ov.contentView = v
            ov.orderFrontRegardless()
            Log.w("0.5 Lite overlay shown on \(screen.frame)")
        case .full:
            let v = FullView(frame: NSRect(origin: .zero, size: screen.frame.size)); full = v; ov.contentView = v
            ov.orderFrontRegardless()
            capture.onFrame = { [weak self] pb in DispatchQueue.main.async { guard let self, self.mode == .full else { return }; self.full?.frame_ = pb; self.full?.render() } }
            Task { @MainActor in
                do {
                    let r = try await capture.start()
                    Log.w(String(format: "0.7 Full: stream started %.0f ms, first frame %.0f ms", r.startMs, r.firstFrameMs))
                    startFPS()
                } catch { Log.w("0.7 Full: start failed: \(error.localizedDescription)") }
            }
        case .off: break
        }
        apply(progress: slider.doubleValue)
    }

    private func teardownOverlay() {
        fpsTimer?.invalidate(); fpsTimer = nil
        if capture.isRunning { Task { await capture.stop(); Log.w("stream stopped") } }
        capture.onFrame = nil
        overlay?.orderOut(nil); overlay = nil; lite = nil; full = nil
    }

    private func startFPS() {
        lastDrawCount = full?.drawCount ?? 0
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let f = self.full else { return }
            let d = f.drawCount - self.lastDrawCount; self.lastDrawCount = f.drawCount
            Log.w("0.7 fps=\(d) frames=\(self.capture.frameCount) progress=\(String(format: "%.2f", self.slider.doubleValue))")
        }
    }

    @objc private func measureStart() {
        guard mode == .off else { Log.w("0.3 set Overlay: Off first"); return }
        Task { @MainActor in
            var starts: [Double] = [], firsts: [Double] = []
            for i in 1...10 {
                do {
                    let r = try await capture.start()
                    starts.append(r.startMs); firsts.append(r.firstFrameMs)
                    Log.w(String(format: "0.3 run %d: startCapture %.0f ms, first frame %.0f ms", i, r.startMs, r.firstFrameMs))
                    await capture.stop()
                    try await Task.sleep(nanoseconds: 300_000_000)
                } catch { Log.w("0.3 run \(i) failed: \(error.localizedDescription)"); await capture.stop() }
            }
            if !firsts.isEmpty {
                Log.w(String(format: "0.3 SUMMARY startCapture avg %.0f max %.0f ms | first frame avg %.0f max %.0f ms",
                             starts.reduce(0,+)/Double(starts.count), starts.max()!, firsts.reduce(0,+)/Double(firsts.count), firsts.max()!))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { teardownOverlay() }
}
