import Foundation

/// Decodes the lid angle sensor's HID feature reports.
///
/// Report 1 is `[1, lo, hi]` in whole degrees; report 7 is `[7, lo, hi, 0, 0]`
/// in hundredths of a degree. Both are little-endian 16-bit values.
public enum LidAngleReport {
    public static let wholeDegrees: UInt8 = 1
    public static let hundredths: UInt8 = 7

    /// Angle in degrees, or `nil` for a report this decoder doesn't know.
    public static func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3 else { return nil }
        let raw = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        switch bytes[0] {
        case wholeDegrees: return raw
        case hundredths: return raw / 100
        default: return nil
        }
    }

    /// A fully closed lid reads 0° and then wraps to ~359.9°.
    /// Anything past 180° is the closed side of that wrap.
    public static func normalize(_ degrees: Double) -> Double {
        degrees > 180 ? 0 : degrees
    }
}
