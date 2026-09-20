import Foundation

/// Whether this Mac model is known to have a lid angle sensor. The runtime
/// probe (`HIDLidAngleReader.init`) has the final word; this exists so the
/// app can say *why* when the probe fails.
public enum LidHardwareSupport: Equatable, Sendable {
    case supported(model: String)
    case unsupported(reason: String)
    case unknown(modelIdentifier: String)
}

public enum LidHardware {
    /// `hw.model`, e.g. "Mac15,6".
    public static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    public static func support(for id: String = modelIdentifier()) -> LidHardwareSupport {
        if let name = supportedModels[id] { return .supported(model: name) }
        if let reason = unsupportedReason(for: id) { return .unsupported(reason: reason) }
        return .unknown(modelIdentifier: id)
    }

    // Model table from samhenrigold/LidAngleSensor (MIT), HardwareCompat.swift,
    // plus Mac15,6 confirmed here in Phase 0.
    static let supportedModels: [String: String] = [
        // MacBook Pro 16-inch, 2019 — the only Intel model with the sensor
        "MacBookPro16,1": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,4": "MacBook Pro (16-inch, 2019)",
        // 2021 (M1 Pro/Max)
        "MacBookPro18,3": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,4": "MacBook Pro (14-inch, 2021)",
        "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
        "MacBookPro18,2": "MacBook Pro (16-inch, 2021)",
        // Jan 2023 (M2 Pro/Max)
        "Mac14,9": "MacBook Pro (14-inch, 2023)",
        "Mac14,5": "MacBook Pro (14-inch, 2023)",
        "Mac14,10": "MacBook Pro (16-inch, 2023)",
        "Mac14,6": "MacBook Pro (16-inch, 2023)",
        // Nov 2023 (M3)
        "Mac15,3": "MacBook Pro (14-inch, M3, Nov 2023)",
        "Mac15,6": "MacBook Pro (14-inch, M3 Pro, Nov 2023)",
        "Mac15,8": "MacBook Pro (14-inch, M3 Max, Nov 2023)",
        "Mac15,7": "MacBook Pro (16-inch, M3 Pro, Nov 2023)",
        "Mac15,9": "MacBook Pro (16-inch, M3 Max, Nov 2023)",
        "Mac15,11": "MacBook Pro (16-inch, M3 Max, Nov 2023)",
        // 2024 (M4)
        "Mac16,1": "MacBook Pro (14-inch, M4, 2024)",
        "Mac16,6": "MacBook Pro (14-inch, M4 Pro, 2024)",
        "Mac16,8": "MacBook Pro (14-inch, M4 Max, 2024)",
        "Mac16,5": "MacBook Pro (16-inch, M4 Pro, 2024)",
        "Mac16,7": "MacBook Pro (16-inch, M4 Pro, 2024)",
        "Mac16,9": "MacBook Pro (16-inch, M4 Max, 2024)",
        "Mac16,10": "MacBook Pro (16-inch, M4 Max, 2024)",
        // MacBook Air (M2+)
        "Mac14,2": "MacBook Air (M2, 2022)",
        "Mac14,15": "MacBook Air (15-inch, M2, 2023)",
        "Mac16,12": "MacBook Air (13-inch, M4, 2025)",
        "Mac16,13": "MacBook Air (15-inch, M4, 2025)",
    ]

    static func unsupportedReason(for id: String) -> String? {
        if ["Macmini", "MacPro", "iMac"].contains(where: { id.hasPrefix($0) })
            || ["Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14", "Mac16,2", "Mac16,3", "Mac16,4", "Mac16,11"].contains(id) {
            return "Desktop Macs have no lid."
        }
        if ["MacBookPro17,1", "Mac14,7", "MacBookPro15,2", "MacBookPro15,4", "MacBookPro16,2", "MacBookPro16,3"].contains(id) {
            return "The 13-inch MacBook Pro has no lid angle sensor."
        }
        if ["MacBookPro15,1", "MacBookPro15,3"].contains(id)
            || ["MacBookPro14,", "MacBookPro13,", "MacBookPro12,", "MacBookPro11,", "MacBookPro10,"].contains(where: { id.hasPrefix($0) }) {
            return "This MacBook Pro predates the lid angle sensor (introduced with the 16-inch, 2019)."
        }
        if id.hasPrefix("MacBookAir") {
            return "Only MacBook Air models from M2 (2022) onward have a lid angle sensor."
        }
        if id.hasPrefix("MacBook"), !id.hasPrefix("MacBookPro"), !id.hasPrefix("MacBookAir") {
            return "The 12-inch MacBook has no lid angle sensor."
        }
        return nil
    }
}
