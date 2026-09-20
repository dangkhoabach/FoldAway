import Testing
@testable import DKBClamshellCore

@Suite struct LidHardwareTests {
    @Test func thisMacAndTheTableAgree() {
        #expect(LidHardware.support(for: "Mac15,6") == .supported(model: "MacBook Pro (14-inch, M3 Pro, Nov 2023)"))
        #expect(LidHardware.support(for: "MacBookPro16,1") == .supported(model: "MacBook Pro (16-inch, 2019)"))
    }

    @Test func knownMisses() {
        #expect(LidHardware.support(for: "Mac14,7") == .unsupported(reason: "The 13-inch MacBook Pro has no lid angle sensor."))
        #expect(LidHardware.support(for: "MacBookAir10,1") == .unsupported(reason: "Only MacBook Air models from M2 (2022) onward have a lid angle sensor."))
        #expect(LidHardware.support(for: "Macmini9,1") == .unsupported(reason: "Desktop Macs have no lid."))
        #expect(LidHardware.support(for: "Mac13,1") == .unsupported(reason: "Desktop Macs have no lid."))
        #expect(LidHardware.support(for: "MacBookPro15,1") == .unsupported(reason: "This MacBook Pro predates the lid angle sensor (introduced with the 16-inch, 2019)."))
        #expect(LidHardware.support(for: "MacBook10,1") == .unsupported(reason: "The 12-inch MacBook has no lid angle sensor."))
    }

    @Test func futureModelsAreUnknownNotRejected() {
        #expect(LidHardware.support(for: "Mac17,9") == .unknown(modelIdentifier: "Mac17,9"))
    }

    @Test func modelIdentifierIsNonEmpty() {
        #expect(!LidHardware.modelIdentifier().isEmpty)
    }
}
