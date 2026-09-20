import Foundation

/// The overlay's lifecycle (plan §5.2), driven only by angles and a few
/// system events. Pure: no timers, no clock of its own — the app feeds it.
///
/// The effect starts from wherever the lid was *resting* (iPhone Duo's
/// transition begins the moment the hinge moves, not at a fixed angle):
///
///     idle ──(closing)──▶ prewarm ──(angle < rest − startOffset)──▶ active
///     active / prewarm ──(back above start and still for releaseDelay, or screens slept)──▶ idle
///     unlock: angle < start ──▶ active · otherwise ──▶ reveal ──(revealFinished)──▶ idle
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
    public static let releaseDelay = 2.0      // s back above `startAngle` before going idle

    public var endAngle: Double
    public private(set) var phase: FoldPhase = .idle
    /// Where the lid sat before it started closing; tracked while idle.
    public private(set) var restAngle: Double?
    private var aboveStartSince: TimeInterval?

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
        if angle >= startAngle, !isMoving {
            if aboveStartSince == nil { aboveStartSince = time }
        } else {
            aboveStartSince = nil
        }
        switch phase {
        case .idle:
            if restAngle == nil { restAngle = angle }
            if angle < startAngle { phase = .active }
            else if isMoving, velocity < 0 { phase = .prewarm }
        case .prewarm:
            if angle < startAngle { phase = .active }
            else if released(at: time) { phase = .idle; restAngle = angle }
        case .active:
            if released(at: time) { phase = .idle; restAngle = angle }
        case .reveal:
            break
        }
    }

    private func released(at time: TimeInterval) -> Bool {
        guard let since = aboveStartSince else { return false }
        return time - since >= Self.releaseDelay
    }

    /// `screensDidSleepNotification` / `willSleepNotification`: nothing to draw.
    public mutating func screensDidSleep() {
        phase = .idle
        aboveStartSince = nil
    }

    /// `com.apple.screenIsUnlocked` (D11).
    public mutating func screenUnlocked(angle: Double) {
        phase = angle < startAngle ? .active : .reveal
        aboveStartSince = nil
    }

    public mutating func revealFinished() {
        if phase == .reveal { phase = .idle }
    }
}
