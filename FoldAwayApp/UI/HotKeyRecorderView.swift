import AppKit
import SwiftUI

/// Settings › Shortcuts row: shows the shortcut, and while recording takes
/// the next key press (with ⌘/⌥/⌃) as the new one (ported from KeyCellar).
struct HotKeyRecorderView: View {
    let title: LocalizedStringKey
    let action: HotKeyAction
    let manager: HotKeyManager
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Button(recording ? "Press keys…" : "\(manager.hotKey(for: action).displayString)") {
                        recording ? stop() : start()
                    }
                    .frame(minWidth: 110)
                    if recording {
                        Button("Cancel") { stop() }
                    }
                }
                if manager.failed.contains(action) {
                    Label("Another app already uses this shortcut, so it does nothing here. Choose a different one.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in stop() }
                return nil
            }
            if let hotKey = HotKey(event: event) {
                Task { @MainActor in
                    manager.update(action, to: hotKey)
                    stop()
                }
                return nil
            }
            return event
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
