import Foundation
import IOKit.hid

/// Reads the lid angle sensor the way that was proven to work on Mac15,6:
/// match the HID Sensor page (0x20) / Orientation usage (0x8A), open the
/// device once, and pull feature report 7 (0.01°) — falling back to report 1
/// (whole degrees) if 7 ever fails. Matching by vendor/product id and opening
/// through the manager returned `kIOReturnUnsupported` in testing, so
/// this deliberately doesn't.
///
/// The sensor itself only refreshes every 100 ms; reading
/// faster than that just returns the same value.
public final class HIDLidAngleReader: LidAngleReading, @unchecked Sendable {
    private let device: IOHIDDevice
    private let lock = NSLock()
    private var buffer = [UInt8](repeating: 0, count: 8)

    public init() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDPrimaryUsagePageKey: 0x0020,
            kIOHIDPrimaryUsageKey: 0x008A,
        ] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
            throw LidSensorError.notFound
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw LidSensorError.openFailed(result) }
        self.device = device
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func readAngle() throws -> Double {
        lock.lock(); defer { lock.unlock() }
        if let fine = try? report(LidAngleReport.hundredths) { return fine }
        return try report(LidAngleReport.wholeDegrees)
    }

    private func report(_ id: UInt8) throws -> Double {
        var length = CFIndex(buffer.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &length)
        guard result == kIOReturnSuccess else { throw LidSensorError.reportFailed(result) }
        guard let degrees = LidAngleReport.decode(Array(buffer.prefix(length))) else {
            throw LidSensorError.reportFailed(kIOReturnBadArgument)
        }
        return LidAngleReport.normalize(degrees)
    }
}
