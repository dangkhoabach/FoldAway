import Testing
@testable import FoldAwayCore

@Suite struct LidAngleReportTests {
    @Test func report1IsWholeDegrees() {
        #expect(LidAngleReport.decode([1, 110, 0]) == 110)
        #expect(LidAngleReport.decode([1, 0x2C, 0x01]) == 300)
    }

    @Test func report7IsHundredths() {
        // [7, 105, 43] → 11113 → 111.13°, a value read from a real sensor.
        #expect(LidAngleReport.decode([7, 105, 43, 0, 0]) == 111.13)
    }

    @Test func unknownOrShortReportsAreNil() {
        #expect(LidAngleReport.decode([2, 39]) == nil)
        #expect(LidAngleReport.decode([1, 110]) == nil)
        #expect(LidAngleReport.decode([]) == nil)
    }

    @Test func closedLidWrapIsZero() {
        #expect(LidAngleReport.normalize(359.87) == 0)
        #expect(LidAngleReport.normalize(0.03) == 0.03)
        #expect(LidAngleReport.normalize(110) == 110)
    }
}
