import Testing
@testable import DKBClamshellCore

@Suite struct FoldStateMachineTests {
    private func resting(at angle: Double) -> FoldStateMachine {
        var m = FoldStateMachine(endAngle: 25)
        m.update(angle: angle, velocity: 0, isMoving: false, time: 0)
        return m
    }

    @Test func startsFromWhereverTheLidRested() {
        var m = resting(at: 110)
        #expect(m.phase == .idle)
        #expect(m.restAngle == 110)
        #expect(m.startAngle == 107)
        m.update(angle: 108, velocity: -60, isMoving: true, time: 0.1);  #expect(m.phase == .prewarm)
        m.update(angle: 104, velocity: -80, isMoving: true, time: 0.2);  #expect(m.phase == .active)
        #expect(m.progress(angle: 104) > 0)
        #expect(m.progress(angle: 66) == 0.5)          // halfway between 107 and 25
        #expect(m.progress(angle: 20) == 1)
        // A lid that rests lower starts lower.
        var low = resting(at: 90)
        #expect(low.startAngle == 87)
        low.update(angle: 80, velocity: -100, isMoving: true, time: 0.1)
        #expect(low.phase == .active)
    }

    @Test func reopeningReleasesAfterTheLidIsBackAndStill() {
        var m = resting(at: 110)
        m.update(angle: 60, velocity: -100, isMoving: true, time: 0.5);  #expect(m.phase == .active)
        m.update(angle: 112, velocity: 100, isMoving: true, time: 1.5);  #expect(m.phase == .active)
        m.update(angle: 112, velocity: 0, isMoving: false, time: 2.0);   #expect(m.phase == .active)
        m.update(angle: 112, velocity: 0, isMoving: false, time: 3.9);   #expect(m.phase == .active)
        m.update(angle: 112, velocity: 0, isMoving: false, time: 4.0);   #expect(m.phase == .idle)
        #expect(m.restAngle == 112)                    // the new resting angle
        #expect(m.progress(angle: 112) == 0)
    }

    @Test func aHalfClosedLidStaysActive() {
        var m = resting(at: 110)
        m.update(angle: 60, velocity: -100, isMoving: true, time: 0.5)
        m.update(angle: 60, velocity: 0, isMoving: false, time: 5)
        #expect(m.phase == .active)
        #expect(m.progress(angle: 60) > 0.5)
    }

    @Test func openingDoesNotPrewarm() {
        var m = resting(at: 90)
        m.update(angle: 100, velocity: 80, isMoving: true, time: 0.1)
        #expect(m.phase == .idle)
    }

    @Test func prewarmReleasesIfTheLidSettlesBackUp() {
        var m = resting(at: 110)
        m.update(angle: 109, velocity: -20, isMoving: true, time: 0.1);  #expect(m.phase == .prewarm)
        m.update(angle: 110, velocity: 0, isMoving: false, time: 0.5)
        m.update(angle: 110, velocity: 0, isMoving: false, time: 2.6);   #expect(m.phase == .idle)
    }

    @Test func launchingWithTheLidHalfClosedIsActive() {
        var m = FoldStateMachine(endAngle: 25)
        m.update(angle: 60, velocity: 0, isMoving: false, time: 0)
        // Nothing to compare against yet: the first angle is the rest, so the
        // effect waits for actual closing motion.
        #expect(m.phase == .idle)
        m.update(angle: 50, velocity: -60, isMoving: true, time: 0.2)
        #expect(m.phase == .active)
    }

    @Test func sleepingAlwaysGoesIdle() {
        var m = resting(at: 110)
        m.update(angle: 30, velocity: -100, isMoving: true, time: 0.5);  #expect(m.phase == .active)
        m.screensDidSleep();                                             #expect(m.phase == .idle)
        m.update(angle: 30, velocity: 0, isMoving: false, time: 1)
        #expect(m.phase == .idle)                      // a closed, still lid is the new rest…
        #expect(m.restAngle == 30)
        m.update(angle: 20, velocity: -50, isMoving: true, time: 1.2)
        #expect(m.phase == .active)                    // …and closing further from it counts again
    }

    @Test func unlockRevealsByTimerWhenTheLidIsAlreadyOpen() {
        var m = resting(at: 110)
        m.screenUnlocked(angle: 110);  #expect(m.phase == .reveal)
        #expect(m.progress(angle: 110) == 0)
        m.update(angle: 110, velocity: 0, isMoving: false, time: 5)
        #expect(m.phase == .reveal)                    // angle updates don't cut a reveal short
        m.revealFinished();            #expect(m.phase == .idle)
    }

    @Test func unlockWithTheLidHalfOpenFollowsTheSensor() {
        var m = resting(at: 110)
        m.screenUnlocked(angle: 60);   #expect(m.phase == .active)
        #expect(m.progress(angle: 60) > 0)
        m.revealFinished();            #expect(m.phase == .active)
    }
}
