import AppKit

/// AppKit glue SwiftUI Scenes don't expose: apply the theme, start the lid
/// monitor and the global shortcuts, keep running with no windows (menu bar app).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemePreference.apply()
        AppServices.shared.monitor.start()
        AppServices.shared.hotKeys.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
