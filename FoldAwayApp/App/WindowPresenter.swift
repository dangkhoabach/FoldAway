import AppKit
import SwiftUI

/// Brings the Settings window forward (ported from KeyCellar). The app is
/// menu-bar only (`LSUIElement`), so opening the `Settings` scene does not
/// activate it: the window appeared behind whatever app was in front and
/// only showed once everything else was hidden.
@MainActor
enum WindowPresenter {
    /// SwiftUI's own way to open the Settings scene, kept by the status item
    /// (`OpenSettingsKeeper`) for the panel and the right-click menu.
    static var openSettings: OpenSettingsAction?

    static func showSettings() {
        StatusBarController.shared.closePanel()
        openSettings?()
        bringSettingsFront()
    }

    /// Call right after opening Settings; the window exists by the next
    /// run-loop turn.
    static func bringSettingsFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            // Only the Settings window: `NSApp.windows` also lists the overlay,
            // the debug HUD, the menu bar panel and the About window.
            for window in NSApp.windows where window.identifier?.rawValue.contains("Settings") == true {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

/// Keeps SwiftUI's `openSettings` for `WindowPresenter`. It sits, with no
/// size, in the status item, which is there from launch.
struct OpenSettingsKeeper: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { WindowPresenter.openSettings = openSettings }
    }
}
