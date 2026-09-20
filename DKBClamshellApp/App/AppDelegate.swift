import AppKit

/// AppKit glue SwiftUI Scenes don't expose: apply the theme, start the lid
/// monitor, the global shortcuts and the updater, keep running with no
/// windows (menu bar app).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemePreference.apply()
        AppServices.shared.monitor.start()
        AppServices.shared.hotKeys.start()
        _ = AppUpdater.shared   // starts Sparkle's scheduled check (the controller is lazy)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
