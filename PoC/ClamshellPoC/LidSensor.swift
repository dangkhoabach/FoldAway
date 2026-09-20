import Foundation
import IOKit.hid

/// Reads the lid angle sensor the way PoC-B (plan §1) proved works:
/// match Sensor page 0x20 / usage 0x8A, open the device, feature report ID 1 → [1, lo, hi].
final class LidSensor {
    private var device: IOHIDDevice?
    private var report = [UInt8](repeating: 0, count: 8)
    private var timer: DispatchSourceTimer?
    private(set) var angle: Int = -1
    var onAngle: ((Int) -> Void)?

    init?() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDPrimaryUsagePageKey: 0x0020, kIOHIDPrimaryUsageKey: 0x008A] as CFDictionary)
        guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, let dev = devs.first else {
            Log.w("LAS: no HID device (page 0x20 / usage 0x8A)"); return nil
        }
        let kr = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard kr == kIOReturnSuccess else { Log.w("LAS: open failed \(String(format: "0x%x", kr))"); return nil }
        device = dev
        Log.w("LAS: opened")
    }

    func read() -> Int? {
        guard let dev = device else { return nil }
        var len = CFIndex(report.count)
        let kr = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1, &report, &len)
        guard kr == kIOReturnSuccess, len >= 3 else { return nil }
        return Int(report[1]) | Int(report[2]) << 8
    }

    /// Polls at `hz` on a background queue; delivers only changes to `onAngle` on main.
    func start(hz: Int) {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "las", qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: 1.0 / Double(hz))
        t.setEventHandler { [weak self] in
            guard let self, let a = self.read(), a != self.angle else { return }
            self.angle = a
            DispatchQueue.main.async { self.onAngle?(a) }
        }
        t.resume(); timer = t
    }
}
