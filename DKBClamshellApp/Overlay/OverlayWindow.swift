import AppKit

/// The full-screen layer the effect is drawn into (plan D7).
///
/// It has to be an `NSPanel` with `.nonactivatingPanel`: Phase 0.6b showed a
/// plain `NSWindow` vanishes the moment another app enters full screen, at
/// every window level and with every collection behavior. The panel is
/// never key, never takes the mouse, is on every Space, and is excluded from
/// screenshots and screen sharing so the Full renderer can't capture itself.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // The Lite renderer's NSVisualEffectView tints with the appearance;
        // pin it so the Settings theme (NSApp.appearance) cannot turn the
        // fade-to-black into a light haze.
        appearance = NSAppearance(named: .darkAqua)
        // DKB_ALLOW_CAPTURE lets a Debug build be screenshotted while tuning
        // the effect (same convention as DKB Secret); it does not exist in Release.
        #if DEBUG
        sharingType = ProcessInfo.processInfo.environment["DKB_ALLOW_CAPTURE"] == nil ? .none : .readOnly
        #else
        sharingType = .none
        #endif
    }

    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
    }
}
