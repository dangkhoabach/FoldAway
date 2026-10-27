import AppKit

/// Brings the Settings window forward (ported from DKB Secret). The app is
/// menu-bar only (`LSUIElement`), so opening the `Settings` scene does not
/// activate it: the window appeared behind whatever app was in front and
/// only showed once everything else was hidden.
@MainActor
enum WindowPresenter {
    /// Call right after `openSettings()`; the window exists by the next
    /// run-loop turn.
    static func bringSettingsFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            // Only the Settings window: `NSApp.windows` also lists the overlay,
            // the debug HUD and the menu bar extra's panel, all `NSPanel`s.
            for window in NSApp.windows where !(window is NSPanel) && window.level == .normal {
                window.makeKeyAndOrderFront(nil)
            }
            // The menu bar extra's panel does not close by itself when one
            // of the app's own windows takes over; DKB Monitor gets that for
            // free from switching to a regular (Dock) app, this app stays
            // an accessory.
            for window in NSApp.windows where String(describing: type(of: window)).contains("MenuBarExtra") {
                window.orderOut(nil)
            }
        }
    }
}
