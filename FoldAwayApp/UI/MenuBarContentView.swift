import SwiftUI

/// `MenuBarExtra`'s label — a template `Image` (auto-tinted for light/dark
/// menu bars) that swaps to a slashed laptop while the effect is off and to
/// a warning triangle when the sensor is missing, so the state is visible
/// without opening the menu.
struct MenuBarIconView: View {
    private let services = AppServices.shared

    var body: some View {
        switch services.monitor.status {
        case .running, .notStarted:
            Image(systemName: services.preferences.isEnabled ? "laptopcomputer" : "laptopcomputer.slash")
        case .unsupported, .sensorError:
            Image(systemName: "exclamationmark.triangle")
        }
    }
}

/// The menu bar dropdown, a real SwiftUI panel (`.menuBarExtraStyle(.window)`)
/// laid out like SignalBar's: header with the state, the live readings,
/// then plain full-width rows for the actions.
struct MenuBarContentView: View {
    private let services = AppServices.shared

    var body: some View {
        @Bindable var prefs = services.preferences
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            Toggle(isOn: $prefs.isEnabled) {
                HStack {
                    Text("Fold effect")
                    Spacer()
                    Text(services.hotKeys.hotKey(for: .toggleEffect).displayString)
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            readings
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("FoldAway").font(.headline)
            Spacer()
            Label { statusText } icon: { Image(systemName: statusSymbol) }
                .font(.caption)
                .foregroundStyle(statusIsProblem ? .red : .secondary)
        }
    }

    @ViewBuilder
    private var readings: some View {
        switch services.monitor.status {
        case .running:
            HStack(spacing: 14) {
                if let angle = services.monitor.lastAngle {
                    Label("\(Int(angle.rounded()))°", systemImage: "angle")
                }
                Label(services.monitor.rendererIsFull ? "Full" : "Lite", systemImage: "sparkles.rectangle.stack")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        case .unsupported(let reason), .sensorError(let reason):
            Text(reason).font(.caption).foregroundStyle(.secondary)
        case .notStarted:
            EmptyView()
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            menuButton("Settings…", systemImage: "gearshape") {
                openSettings()
                WindowPresenter.bringSettingsFront()
            }
            menuButton("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") { AppUpdater.checkForUpdates() }
            menuButton("Quit", systemImage: "power") { NSApp.terminate(nil) }
        }
    }

    @Environment(\.openSettings) private var openSettings

    private var statusText: Text {
        switch services.monitor.status {
        case .running: Text(services.preferences.isEnabled ? "Ready" : "Off")
        case .notStarted: Text("Starting…")
        case .unsupported: Text("Not supported")
        case .sensorError: Text("Sensor error")
        }
    }

    private var statusSymbol: String {
        switch services.monitor.status {
        case .running: services.preferences.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
        case .notStarted: "circle.dotted"
        case .unsupported, .sensorError: "exclamationmark.triangle.fill"
        }
    }

    private var statusIsProblem: Bool {
        switch services.monitor.status {
        case .running, .notStarted: false
        case .unsupported, .sensorError: true
        }
    }

    /// Plain full-width rows with a hover highlight — `.menuBarExtraStyle(.window)`
    /// hosts a real view, so it gets no menu-item styling for free (SignalBar).
    private func menuButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .background(.quaternary.opacity(0.001), in: RoundedRectangle(cornerRadius: 5))
    }
}
