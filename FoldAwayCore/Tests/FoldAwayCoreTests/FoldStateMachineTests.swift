import Testing
@testable import FoldAwayCore

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
        m.update(angle: 112, velocity: 0, isMoving: false, time: 2.9);   #expect(m.phase == .active)
        m.update(angle: 112, velocity: 0, isMoving: false, time: 3.0);   #expect(m.phase == .idle)
        #expect(m.restAngle == 112)                    // the new resting angle
        #expect(m.progress(angle: 112) == 0)
    }

    @Test func aLidParkedHalfWayGivesTheScreenBackAndRestsThere() {
        var m = resting(at: 110)
        m.update(angle: 60, velocity: -100, isMoving: true, time: 0.5);  #expect(m.phase == .active)
        m.update(angle: 60, velocity: 0, isMoving: false, time: 1.0);    #expect(m.phase == .active)
        #expect(m.progress(angle: 60) > 0.5)
        m.update(angle: 60, velocity: 0, isMoving: false, time: 1.9);    #expect(m.phase == .active)
        m.update(angle: 60, velocity: 0, isMoving: false, time: 2.0);    #expect(m.phase == .idle)
        #expect(m.restAngle == 60)
        #expect(m.progress(angle: 60) == 0)
        // Closing on from there counts from the new rest.
        #expect(m.startAngle == 57)
        m.update(angle: 50, velocity: -80, isMoving: true, time: 2.5);   #expect(m.phase == .active)
    }

    @Test func aHesitationMidCloseDoesNotRelease() {
        var m = resting(at: 110)
        m.update(angle: 70, velocity: -100, isMoving: true, time: 0.5);  #expect(m.phase == .active)
        m.update(angle: 70, velocity: 0, isMoving: false, time: 1.0)
        m.update(angle: 70, velocity: 0, isMoving: false, time: 1.8);    #expect(m.phase == .active)
        m.update(angle: 55, velocity: -100, isMoving: true, time: 1.9);  #expect(m.phase == .active)
        m.update(angle: 55, velocity: 0, isMoving: false, time: 2.5)
        m.update(angle: 55, velocity: 0, isMoving: false, time: 3.4);    #expect(m.phase == .active) // the clock restarted at 2.5
        m.update(angle: 55, velocity: 0, isMoving: false, time: 3.5);    #expect(m.phase == .idle)
    }

    @Test func aClosedLidStaysFoldedUntilTheScreensSleep() {
        var m = resting(at: 110)
        m.update(angle: 10, velocity: -100, isMoving: true, time: 0.5);  #expect(m.phase == .active)
        m.update(angle: 10, velocity: 0, isMoving: false, time: 1.0)
        m.update(angle: 10, velocity: 0, isMoving: false, time: 6.0);    #expect(m.phase == .active)
        #expect(m.progress(angle: 10) == 1)
        // Reopened before the Mac slept: the sensor unfolds it, then it rests.
        m.update(angle: 80, velocity: 100, isMoving: true, time: 6.5);   #expect(m.phase == .active)
        #expect(m.progress(angle: 80) > 0)
        m.update(angle: 80, velocity: 0, isMoving: false, time: 7.0)
        m.update(angle: 80, velocity: 0, isMoving: false, time: 8.0);    #expect(m.phase == .idle)
        #expect(m.restAngle == 80)
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

    /// The black screen after opening the lid: the screens slept with the
    /// lid shut, and the next poll — the lid still at 0° — folded it again.
    @Test func aClosedLidDoesNotFoldAgainAfterTheScreensSleep() {
        var m = resting(at: 110)
        m.update(angle: 0, velocity: -100, isMoving: true, time: 0.5);  #expect(m.phase == .active)
        m.screensDidSleep();                                             #expect(m.phase == .idle)
        m.update(angle: 2, velocity: -60, isMoving: true, time: 0.6);    #expect(m.phase == .idle)  // still settling
        m.update(angle: 0, velocity: -60, isMoving: true, time: 0.7);    #expect(m.phase == .idle)
        m.update(angle: 0, velocity: 0, isMoving: false, time: 1.0);     #expect(m.phase == .idle)
        // Opened after waking: nothing to unfold, it just rests where it stops…
        m.update(angle: 60, velocity: 200, isMoving: true, time: 9.0);   #expect(m.phase == .idle)
        m.update(angle: 110, velocity: 0, isMoving: false, time: 9.5);   #expect(m.phase == .idle)
        #expect(m.restAngle == 110)
        // …and closing from there counts again.
        m.update(angle: 100, velocity: -80, isMoving: true, time: 10);   #expect(m.phase == .active)
    }

    @Test func unlockRevealsByTimerWhenTheLidIsAlreadyOpen() {
        var m = resting(at: 110)
        m.screenUnlocked(angle: 110);  #expect(m.phase == .reveal)
        #expect(m.progress(angle: 110) == 0)
        m.update(angle: 110, velocity: 0, isMoving: false, time: 5)
        #expect(m.phase == .reveal)                    // angle updates don't cut a reveal short
        m.revealFinished();            #expect(m.phase == .idle)
    }

    /// The usual way: lid shut, the Mac slept, lid opened, Touch ID. Sleep
    /// cleared the resting angle, so the lid is not taken for one mid-close.
    @Test func afterASleepUnlockingAnOpenLidReveals() {
        var m = resting(at: 110)
        m.screensDidSleep()
        m.screenUnlocked(angle: 110);  #expect(m.phase == .reveal)
        #expect(m.progress(angle: 110) == 0)
        m.revealFinished();            #expect(m.phase == .idle)
    }

    @Test func afterASleepUnlockingANearlyShutLidShowsNothing() {
        var m = resting(at: 110)
        m.screensDidSleep()
        m.screenUnlocked(angle: 20);   #expect(m.phase == .idle)
    }

    @Test func unlockWithTheLidHalfOpenFollowsTheSensor() {
        var m = resting(at: 110)
        m.screenUnlocked(angle: 60);   #expect(m.phase == .active)
        #expect(m.progress(angle: 60) > 0)
        m.revealFinished();            #expect(m.phase == .active)
    }
}
