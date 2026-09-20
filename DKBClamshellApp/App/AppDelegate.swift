import AppKit

/// AppKit glue SwiftUI Scenes don't expose: start the lid monitor and keep
/// running with no windows (menu bar app).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppServices.shared.monitor.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
