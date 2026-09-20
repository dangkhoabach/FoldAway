import SwiftUI

/// Placeholder until Phase 4 (plan F3): status, enable toggle, Settings, Quit.
struct MenuBarContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DKB Clamshell").font(.headline)
            Text("Effect not wired yet — Phase 3.").foregroundStyle(.secondary)
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 240)
    }
}
