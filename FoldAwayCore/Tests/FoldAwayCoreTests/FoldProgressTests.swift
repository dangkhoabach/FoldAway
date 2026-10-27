import Testing
@testable import FoldAwayCore

@Suite struct FoldProgressTests {
    @Test func endpointsAndClamp() {
        #expect(FoldProgress.progress(angle: 85, start: 85, end: 25) == 0)
        #expect(FoldProgress.progress(angle: 120, start: 85, end: 25) == 0)
        #expect(FoldProgress.progress(angle: 25, start: 85, end: 25) == 1)
        #expect(FoldProgress.progress(angle: 0, start: 85, end: 25) == 1)
        #expect(FoldProgress.progress(angle: 55, start: 85, end: 25) == 0.5)
    }

    @Test func monotonicWhileClosing() {
        var previous = -1.0
        for angle in stride(from: 90.0, through: 20.0, by: -1) {
            let p = FoldProgress.progress(angle: angle, start: 85, end: 25)
            #expect(p >= previous); previous = p
        }
    }

    @Test func invertedRangeIsAStepNotACrash() {
        #expect(FoldProgress.progress(angle: 50, start: 25, end: 85) == 1)
        #expect(FoldProgress.progress(angle: 90, start: 25, end: 85) == 0)
    }
}
