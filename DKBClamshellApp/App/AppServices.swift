import Foundation

/// The app's long-lived objects, created once at launch.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let preferences = AppPreferences()
    let monitor: LidMonitor

    private init() {
        monitor = LidMonitor(preferences: preferences)
    }
}
