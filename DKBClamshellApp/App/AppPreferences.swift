import Foundation
import Observation

/// Which overlay renderer to use (plan D5). `auto` picks Full whenever the
/// Screen Recording permission is granted and Lite otherwise.
enum RendererMode: String, CaseIterable, Identifiable {
    case auto, lite, full
    var id: Self { self }
}

/// The user-tunable settings (plan §5.4), persisted in `UserDefaults` the
/// moment they change. Nothing else in the app keeps its own copy.
@MainActor
@Observable
final class AppPreferences {
    static let defaultEndAngle = 25

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) } }
    /// Where the effect is complete. It starts from wherever the lid rested
    /// (plan D10), so there is no start angle to configure.
    var endAngle: Int { didSet { defaults.set(endAngle, forKey: Keys.endAngle) } }
    var intensity: Double { didSet { defaults.set(intensity, forKey: Keys.intensity) } }
    var maxDarkness: Double { didSet { defaults.set(maxDarkness, forKey: Keys.maxDarkness) } }
    var revealOnOpen: Bool { didSet { defaults.set(revealOnOpen, forKey: Keys.revealOnOpen) } }
    var rendererMode: RendererMode { didSet { defaults.set(rendererMode.rawValue, forKey: Keys.rendererMode) } }
    var showDebugHUD: Bool { didSet { defaults.set(showDebugHUD, forKey: Keys.showDebugHUD) } }

    private let defaults: UserDefaults

    enum Keys {
        static let isEnabled = "effect.enabled"
        static let endAngle = "effect.endAngle"
        static let intensity = "effect.intensity"
        static let maxDarkness = "effect.maxDarkness"
        static let revealOnOpen = "effect.revealOnOpen"
        static let rendererMode = "renderer.mode"
        static let showDebugHUD = "debug.hud"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        let end = defaults.object(forKey: Keys.endAngle) as? Int ?? Self.defaultEndAngle
        endAngle = (0...90).contains(end) ? end : Self.defaultEndAngle
        intensity = Self.unit(defaults.object(forKey: Keys.intensity) as? Double) ?? 1
        maxDarkness = Self.unit(defaults.object(forKey: Keys.maxDarkness) as? Double) ?? 1
        revealOnOpen = defaults.object(forKey: Keys.revealOnOpen) as? Bool ?? true
        rendererMode = defaults.string(forKey: Keys.rendererMode).flatMap(RendererMode.init(rawValue:)) ?? .auto
        showDebugHUD = defaults.bool(forKey: Keys.showDebugHUD)
    }

    private static func unit(_ value: Double?) -> Double? {
        guard let value, (0...1).contains(value) else { return nil }
        return value
    }
}
