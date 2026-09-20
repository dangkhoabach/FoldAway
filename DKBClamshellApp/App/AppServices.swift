import Foundation

/// The app's long-lived objects, created once at launch.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let preferences = AppPreferences()
    let monitor: LidMonitor
    let hotKeys: HotKeyManager

    private init() {
        let preferences = self.preferences
        let monitor = LidMonitor(preferences: preferences)
        self.monitor = monitor
        // The shortcuts exist for the moment the screen is unreadable, so
        // both hide the overlay first and change the settings second.
        hotKeys = HotKeyManager { action in
            monitor.dismiss()
            switch action {
            case .toggleEffect: preferences.isEnabled.toggle()
            case .resetEffect: preferences.resetEffect()
            }
        }
    }
}
