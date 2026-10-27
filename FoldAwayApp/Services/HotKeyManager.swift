import AppKit
import Carbon.HIToolbox
import Observation

/// The two global shortcuts, for when a wrong setting has left the screen
/// unreadable and the menu bar cannot be reached by eye.
enum HotKeyAction: String, CaseIterable, Identifiable {
    /// Turn the effect off (and hide anything it is showing) or back on.
    case toggleEffect
    /// Put every effect setting back to its default and hide the overlay.
    case resetEffect

    var id: Self { self }

    var defaultHotKey: HotKey {
        switch self {
        case .toggleEffect: HotKey(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))
        case .resetEffect: HotKey(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))
        }
    }

    /// Carbon identifies a registered shortcut by a small integer.
    var carbonID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }

    var keyCodeSetting: String { "hotkey.\(rawValue).keyCode" }
    var modifiersSetting: String { "hotkey.\(rawValue).modifiers" }
}

/// A key combination: Carbon key code + Carbon modifier mask (ported from
/// KeyCellar).
struct HotKey: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// From an `NSEvent` in the recorder. `nil` when the press has no
    /// ⌘/⌥/⌃ — a bare letter must never become a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }

    /// "⌃⌥⌘E" for Settings and the menu bar panel.
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(keyCode)] { return name }
        // Letters/digits/punctuation: ask the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let layout = unsafeBitCast(CFDataGetBytePtr(unsafeBitCast(layoutData, to: CFData.self)), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                    UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // MARK: Persistence

    static func load(_ action: HotKeyAction, from defaults: UserDefaults) -> HotKey {
        guard let code = defaults.object(forKey: action.keyCodeSetting) as? UInt32,
              let mods = defaults.object(forKey: action.modifiersSetting) as? UInt32
        else { return action.defaultHotKey }
        return HotKey(keyCode: code, carbonModifiers: mods)
    }

    func save(_ action: HotKeyAction, to defaults: UserDefaults) {
        defaults.set(keyCode, forKey: action.keyCodeSetting)
        defaults.set(carbonModifiers, forKey: action.modifiersSetting)
    }
}

/// Registers the global shortcuts with Carbon's `RegisterEventHotKey` — no
/// Accessibility permission, and they fire while the overlay covers the
/// screen. One handler for the app; each combination can be swapped at
/// runtime from Settings.
@MainActor
@Observable
final class HotKeyManager {
    private(set) var hotKeys: [HotKeyAction: HotKey] = [:]
    /// Carbon refused the combination — another app holds it globally.
    private(set) var failed: Set<HotKeyAction> = []
    private let defaults: UserDefaults
    private let onPress: (HotKeyAction) -> Void
    private var registrations: [HotKeyAction: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    /// Carbon calls a C function; it can't capture, so it finds us here.
    nonisolated(unsafe) private static var current: HotKeyManager?

    init(defaults: UserDefaults = .standard, onPress: @escaping (HotKeyAction) -> Void) {
        self.defaults = defaults
        self.onPress = onPress
        for action in HotKeyAction.allCases { hotKeys[action] = HotKey.load(action, from: defaults) }
    }

    func hotKey(for action: HotKeyAction) -> HotKey {
        hotKeys[action] ?? action.defaultHotKey
    }

    func start() {
        Self.current = self
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                if let action = HotKeyAction.allCases.first(where: { $0.carbonID == id.id }) {
                    Task { @MainActor in HotKeyManager.current?.onPress(action) }
                }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        for action in HotKeyAction.allCases { register(action) }
    }

    func update(_ action: HotKeyAction, to newValue: HotKey) {
        hotKeys[action] = newValue
        newValue.save(action, to: defaults)
        register(action)
    }

    private func register(_ action: HotKeyAction) {
        if let old = registrations[action] { UnregisterEventHotKey(old) }
        registrations[action] = nil
        let id = EventHotKeyID(signature: OSType(0x444B4243), id: action.carbonID) // "DKBC"
        let hotKey = hotKey(for: action)
        var ref: EventHotKeyRef?
        if RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr {
            registrations[action] = ref
            failed.remove(action)
        } else {
            failed.insert(action)
        }
    }
}
