import Carbon.HIToolbox
import Foundation
import Testing
@testable import DKB_Clamshell

@Suite struct HotKeyTests {
    @Test func displayStringListsModifiersInTheMacOrder() {
        let key = HotKey(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(key.displayString == "⌃⌥⇧⌘E")
        #expect(HotKey(keyCode: UInt32(kVK_Escape), carbonModifiers: UInt32(cmdKey)).displayString == "⌘⎋")
    }

    @Test func defaultsDifferPerActionAndRoundTrip() {
        let name = "HotKeyTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        #expect(HotKey.load(.toggleEffect, from: d) == HotKeyAction.toggleEffect.defaultHotKey)
        #expect(HotKeyAction.toggleEffect.defaultHotKey != HotKeyAction.resetEffect.defaultHotKey)
        let custom = HotKey(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(optionKey))
        custom.save(.resetEffect, to: d)
        #expect(HotKey.load(.resetEffect, from: d) == custom)
        #expect(HotKey.load(.toggleEffect, from: d) == HotKeyAction.toggleEffect.defaultHotKey)
    }

    @Test func carbonIDsAreDistinctAndNonZero() {
        let ids = HotKeyAction.allCases.map(\.carbonID)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(0))
    }
}
