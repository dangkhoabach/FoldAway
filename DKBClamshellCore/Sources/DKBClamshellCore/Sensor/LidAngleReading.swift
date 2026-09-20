import Foundation

/// A source of lid angles in degrees, 0 = closed. The real one is
/// `HIDLidAngleReader`; tests feed recorded angles instead.
public protocol LidAngleReading: Sendable {
    func readAngle() throws -> Double
}

public enum LidSensorError: Error, Equatable {
    /// No HID device on the Sensor page with the Orientation usage — this
    /// Mac has no lid angle sensor (or macOS doesn't expose it).
    case notFound
    case openFailed(Int32)
    case reportFailed(Int32)
}
