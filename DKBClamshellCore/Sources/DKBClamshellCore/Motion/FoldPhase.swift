import Foundation

/// The overlay's lifecycle (plan §5.2), driven only by angles and a few
/// system events. Pure: no timers, no clock of its own — the app feeds it.
///
/// The effect starts from wherever the lid was *resting* (iPhone Duo's
/// transition begins the moment the hinge moves, not at a fixed angle):
///
///     idle ──(closing)──▶ prewarm ──(angle < rest − startOffset)──▶ active
///     active / prewarm ──(still for releaseDelay above endAngle, or screens slept)──▶ idle
///     unlock: angle < start ──▶ active · otherwise ──▶ reveal ──(revealFinished)──▶ idle
///
/// Wherever the lid stops — back where it was, or half-way down — it becomes
/// the new resting angle and the screen is handed back: a lid held at 70° is
/// a lid someone wants to use. Below `endAngle` the screen is already black
/// and the lid is as good as closed, so the effect stays put until the
/// screens sleep (or the lid comes back up and unfolds it).
public enum FoldPhase: Equatable, Sendable {
    case idle
    /// Full renderer starts its capture stream here so the first frame is
    /// ready as soon as possible (Phase 0.3: cold start ~212 ms).
    case prewarm
    case active
    /// Timed 350 ms un-blur after unlocking with the lid already open (D11).
    case reveal
}

public struct FoldStateMachine: Sendable {
    /// How far below the resting angle the effect begins — enough to ignore
    /// a nudge, small enough to feel immediate.
    public static let startOffset = 3.0
    /// How long the lid has to be still before the effect lets go. Long
    /// enough to ride out a hesitation mid-close, short enough that a lid
    /// parked half-way gives the screen back promptly (plus the tracker's
    /// 0.25 s to notice the lid stopped).
    public static let releaseDelay = 1.0

    public var endAngle: Double
    public private(set) var phase: FoldPhase = .idle
    /// Where the lid sat before it started closing; tracked while idle.
    public private(set) var restAngle: Double?
    private var stillSince: TimeInterval?

    public init(endAngle: Double) {
        self.endAngle = endAngle
    }

    /// The angle progress counts from — just under the resting angle.
    public var startAngle: Double {
        max((restAngle ?? 180) - Self.startOffset, endAngle + 1)
    }

    public func progress(angle: Double) -> Double {
        switch phase {
        case .idle, .prewarm, .reveal: return 0
        case .active: return FoldProgress.progress(angle: angle, start: startAngle, end: endAngle)
        }
    }

    /// Feed the displayed angle (from `LidMotionTracker`) every frame.
    public mutating func update(angle: Double, velocity: Double, isMoving: Bool, time: TimeInterval) {
        if phase == .idle, !isMoving { restAngle = angle }
        if isMoving {
            stillSince = nil
        } else if stillSince == nil {
            stillSince = time
        }
        switch phase {
        case .idle:
            if restAngle == nil { restAngle = angle }
            if angle < startAngle { phase = .active }
            else if isMoving, velocity < 0 { phase = .prewarm }
        case .prewarm:
            if angle < startAngle { phase = .active }
            else if released(at: time, angle: angle) { phase = .idle; restAngle = angle }
        case .active:
            if released(at: time, angle: angle) { phase = .idle; restAngle = angle }
        case .reveal:
            break
        }
    }

    private func released(at time: TimeInterval, angle: Double) -> Bool {
        guard angle > endAngle, let since = stillSince else { return false }
        return time - since >= Self.releaseDelay
    }

    /// `screensDidSleepNotification` / `willSleepNotification`: nothing to draw.
    public mutating func screensDidSleep() {
        phase = .idle
        stillSince = nil
    }

    /// `com.apple.screenIsUnlocked` (D11).
    public mutating func screenUnlocked(angle: Double) {
        phase = angle < startAngle ? .active : .reveal
        stillSince = nil
    }

    public mutating func revealFinished() {
        if phase == .reveal { phase = .idle }
    }
}
