import Foundation
import Testing
@testable import FoldAwayCore

@Suite struct LidMotionTrackerTests {
    /// A fast close recorded from a real sensor: ~100°/s, one sample per 100 ms.
    static let fastClose: [(Double, Double)] = [(89.68, 0.0), (85.79, 0.1), (79.31, 0.2), (69.93, 0.3), (58.87, 0.4), (46.31, 0.5), (34.19, 0.6), (23.42, 0.7)]

    @Test func velocityIsNegativeWhileClosingAndPollingSpeedsUp() {
        var t = LidMotionTracker()
        #expect(t.pollInterval == LidMotionTracker.idlePollInterval)
        for (a, time) in Self.fastClose { t.add(LidSample(angle: a, time: time)) }
        #expect(t.velocity < -100)
        #expect(t.isMoving)
        #expect(t.pollInterval == LidMotionTracker.movingPollInterval)
    }

    @Test func firstMoveAfterALongRestGetsARealVelocity() {
        var t = LidMotionTracker()
        t.add(LidSample(angle: 110, time: 0))
        for i in 1...300 { t.add(LidSample(angle: 110.1, time: Double(i) / 30)) }   // 10 s still, noisy
        t.add(LidSample(angle: 104, time: 10.03))
        #expect(t.isMoving)
        #expect(t.velocity < -50)          // 6° over at most one sensor period, not over 10 s
    }

    @Test func pollJitterDoesNotShakeTheVelocity() {
        var t = LidMotionTracker()
        // Changes of exactly −10° per sensor period, but noticed 0 / 33 / 0 / 33 ms late.
        t.add(LidSample(angle: 110, time: 0.000))
        t.add(LidSample(angle: 100, time: 0.133))
        t.add(LidSample(angle: 90, time: 0.200))
        t.add(LidSample(angle: 80, time: 0.333))
        t.add(LidSample(angle: 70, time: 0.400))
        #expect(abs(t.velocity + 100) < 1)
    }

    @Test func repeatedReadsBetweenSensorRefreshesDoNotZeroVelocity() {
        var t = LidMotionTracker()
        t.add(LidSample(angle: 90, time: 0))
        t.add(LidSample(angle: 80, time: 0.1))
        let v = t.velocity
        t.add(LidSample(angle: 80, time: 0.133))   // same value, polled again
        t.add(LidSample(angle: 80, time: 0.2))
        #expect(t.velocity == v)
        #expect(t.isMoving)
    }

    @Test func noiseDoesNotCountAsMovement() {
        var t = LidMotionTracker()
        t.add(LidSample(angle: 111.19, time: 0))
        t.add(LidSample(angle: 111.15, time: 0.1))
        t.add(LidSample(angle: 111.25, time: 0.2))
        #expect(!t.isMoving)
        #expect(t.velocity == 0)
    }

    @Test func goesStillWhenTheSensorStopsChanging() {
        var t = LidMotionTracker()
        t.add(LidSample(angle: 90, time: 0))
        t.add(LidSample(angle: 80, time: 0.1))
        t.add(LidSample(angle: 80, time: 0.3))
        #expect(t.isMoving)                        // one missed refresh is not "still"
        t.add(LidSample(angle: 80, time: 0.4))
        #expect(!t.isMoving)
        #expect(t.velocity == 0)
    }

    @Test func extrapolatesBetweenSamplesInsteadOfSteppingAndConverges() {
        var t = LidMotionTracker()
        t.add(LidSample(angle: 90, time: 0))
        t.add(LidSample(angle: 80, time: 0.1))     // −100°/s
        _ = t.displayAngle(at: 0.1)
        var previous = t.displayAngle(at: 0.1)!
        var steps: [Double] = []
        for frame in 1...5 {                          // 60 fps frames until the next sample
            let now = 0.1 + Double(frame) / 60
            let a = t.displayAngle(at: now)!
            steps.append(previous - a); previous = a
        }
        // Every frame moves the display forward by a small amount — no 10° jump.
        #expect(steps.allSatisfy { $0 > 0 && $0 < 3 })
        // 83 ms after the sample the display sits where the lid should be
        // (80° − 100°/s × 0.083 s ≈ 71.7°) — no steady-state lag.
        #expect(abs(previous - 71.7) < 3)
    }

    @Test func extrapolationIsCappedAndClampedToLidRange() {
        var t = LidMotionTracker()
        t.add(LidSample(angle: 20, time: 0))
        t.add(LidSample(angle: 5, time: 0.1))      // −150°/s, about to hit 0
        var a = 0.0
        for frame in 0...60 { a = t.displayAngle(at: 0.1 + Double(frame) / 60)! }
        #expect(a >= 0)
        #expect(a <= 5)
    }
}
