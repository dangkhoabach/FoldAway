import Foundation

/// One sensor reading. `time` is any monotonic clock in seconds — the app
/// passes `CACurrentMediaTime()`, tests pass whatever they like.
public struct LidSample: Equatable, Sendable {
    public var angle: Double
    public var time: TimeInterval
    public init(angle: Double, time: TimeInterval) { self.angle = angle; self.time = time }
}

/// Turns the sensor's 10 Hz samples into a smooth 60 fps angle (plan D9/D9b).
///
/// The sensor only produces a new value every 100 ms (Phase 0.2: a normal
/// close gets ~6 samples, 3–8° apart). Interpolating *between* known samples
/// would be smooth but 100 ms late; instead the displayed angle is
/// extrapolated from the last sample by its velocity (clamped, and never more
/// than `maxExtrapolation` ahead), then low-passed so a sample that lands off
/// the prediction pulls the display over instead of snapping it. The
/// low-pass would lag a moving target by `velocity × smoothing`, so that much
/// lead is added back — steady-state lag is zero, only corrections are eased.
public struct LidMotionTracker: Sendable {
    public static let movingThreshold = 0.3          // degrees; sensor noise is ±0.05
    public static let maxVelocity = 300.0            // deg/s
    public static let maxExtrapolation = 0.15        // s
    public static let smoothing = 0.04               // s, low-pass time constant
    /// The sensor refreshes every 100 ms. A change is assumed to have happened
    /// within one period, however long the lid was still before it — otherwise
    /// the first sample after a long rest would get a near-zero velocity.
    public static let sensorPeriod = 0.1
    /// No change for this long → the lid is still.
    public static let stillAfter = 0.25
    /// Polling faster than the sensor only shortens how late a change is
    /// noticed (≤ 33 ms); reads cost ~0.2 ms of CPU each.
    public static let pollInterval = 1.0 / 30

    public private(set) var last: LidSample?
    /// Signed, deg/s; negative while closing.
    public private(set) var velocity = 0.0
    public private(set) var isMoving = false
    private var displayed: Double?
    private var displayedAt: TimeInterval = 0

    public init() {}

    /// Feed one reading. Same-value reads (the sensor between refreshes) are
    /// ignored so they don't zero the velocity.
    public mutating func add(_ sample: LidSample) {
        guard let previous = last else {
            last = sample; displayed = sample.angle; displayedAt = sample.time; return
        }
        let delta = sample.angle - previous.angle
        guard abs(delta) >= Self.movingThreshold else {
            if sample.time - previous.time > Self.stillAfter { isMoving = false; velocity = 0 }
            return
        }
        let dt = min(max(sample.time - previous.time, 0.001), Self.sensorPeriod)
        velocity = max(-Self.maxVelocity, min(Self.maxVelocity, delta / dt))
        isMoving = true
        last = sample
    }

    /// The angle to draw at `time`. Call once per frame.
    public mutating func displayAngle(at time: TimeInterval) -> Double? {
        guard let last else { return nil }
        let ahead = isMoving ? min(max(0, time - last.time), Self.maxExtrapolation) + Self.smoothing : 0
        let target = max(0, min(180, last.angle + velocity * ahead))
        guard let current = displayed else { displayed = target; displayedAt = time; return target }
        let dt = max(0, time - displayedAt)
        let alpha = 1 - exp(-dt / Self.smoothing)
        let next = current + (target - current) * alpha
        displayed = next; displayedAt = time
        return next
    }
}
