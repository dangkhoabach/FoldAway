import Testing
@testable import FoldAwayCore

/// Talks to the real sensor. Skips (passes) on Macs without one, such as CI.
@Suite struct HIDLidAngleReaderTests {
    @Test func readsAPlausibleAngleFromTheRealSensor() throws {
        let reader: HIDLidAngleReader
        do { reader = try HIDLidAngleReader() } catch LidSensorError.notFound { return }
        let first = try reader.readAngle()
        let second = try reader.readAngle()
        #expect((0...180).contains(first))
        #expect(abs(first - second) < 1)         // two reads within the same 100 ms refresh
        print("live lid angle: \(first)°")
    }
}
