import SwiftUI

/// The menu bar panel, laid out as in the author's other menu bar apps: a
/// header with the state, the fold effect's switch and live readings, and a
/// footer with the app-level actions. FoldAway has no main window: Settings
/// is the one window it opens.
struct MenuBarPanelView: View {
    static let width: CGFloat = 320

    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue

    var body: some View {
        // The panel is not part of a SwiftUI scene, so the in-app language is
        // applied here rather than inherited.
        MenuBarPanelContent()
            .environment(\.locale, (AppLocale(rawValue: languageRaw) ?? .systemDefault).locale)
            .frame(width: Self.width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                StatusBarController.shared.fitPanel(height: height)
            }
            .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The status item's symbol: a laptop, slashed while the effect is off,
    /// and a warning triangle when the sensor is missing.
    static func iconSymbol(status: LidMonitor.Status, enabled: Bool) -> String {
        switch status {
        case .running, .notStarted: enabled ? "laptopcomputer" : "laptopcomputer.slash"
        case .unsupported, .sensorError: "exclamationmark.triangle"
        }
    }
}

private struct MenuBarPanelContent: View {
    private let services = AppServices.shared

    var body: some View {
        @Bindable var prefs = services.preferences
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 10) {
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack {
            Text(verbatim: "FoldAway").font(.headline)
            Spacer()
            Label { statusText } icon: { Image(systemName: statusSymbol) }
                .font(.caption)
                .foregroundStyle(statusIsProblem ? .red : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
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

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("Settings…", systemImage: "gearshape") { WindowPresenter.showSettings() }
            footerButton("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") { AppUpdater.checkForUpdates() }
            footerButton("About FoldAway", systemImage: "info.circle") { AboutWindow.show() }
            Spacer()
            footerButton("Quit FoldAway", systemImage: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func footerButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }

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
}
