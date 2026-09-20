import AppKit

/// Tiny always-on-top readout of angle / phase / fps (plan D17), toggled in
/// Settings. Lives in the top-right of the built-in display.
@MainActor
final class DebugHUDWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init(screen: NSScreen) {
        let size = NSSize(width: 300, height: 60)
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 12, y: screen.visibleFrame.maxY - size.height - 12)
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.7)
        hasShadow = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 10, y: 8, width: size.width - 20, height: size.height - 16)
        label.maximumNumberOfLines = 3
        contentView?.addSubview(label)
    }

    func show(_ text: String) {
        label.stringValue = text
        if !isVisible { orderFrontRegardless() }
    }
}
