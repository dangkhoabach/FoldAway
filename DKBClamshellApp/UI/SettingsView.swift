import SwiftUI

/// One `Form` with `.formStyle(.grouped)` and a `Section` per topic, like
/// DKB Monitor's and DKB Secret's Settings pages. Every change applies at
/// once — `AppPreferences` is the only copy the app reads.
struct SettingsView: View {
    @AppStorage(ThemePreference.key) private var themeRaw = ThemePreference.system.rawValue
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue
    @State private var loginItemEnabled = LoginItemManager.shared.isEnabled
    @State private var loginItemNeedsApproval = LoginItemManager.shared.requiresApproval
    @State private var loginItemError: String?
    @State private var previewAngle = 180.0
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    /// Mirrors Sparkle's own preference for display only — the write goes
    /// straight back to Sparkle, and `onAppear` re-reads it, so this never
    /// becomes a second source of truth.
    @State private var automaticUpdateChecks = AppUpdater.automaticallyChecksForUpdates
    private let services = AppServices.shared

    var body: some View {
        @Bindable var prefs = services.preferences
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeRaw) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Language", selection: Binding(
                    get: { AppLocale(rawValue: languageRaw) ?? .systemDefault },
                    set: { languageRaw = $0.rawValue }
                )) {
                    Text("VI").tag(AppLocale.vi)
                    Text("EN").tag(AppLocale.en)
                }
                .pickerStyle(.segmented)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(get: { loginItemEnabled }, set: setLoginItem))
                if loginItemNeedsApproval {
                    Label("Waiting for your approval in System Settings › General › Login Items. Until then DKB Clamshell won't start at login.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Fold effect", isOn: $prefs.isEnabled)
            }

            Section("Effect") {
                LabeledContent("Finish closing at") {
                    Slider(value: Binding(get: { Double(prefs.endAngle) }, set: { prefs.endAngle = Int($0) }), in: 10...60, step: 1)
                    Text("\(prefs.endAngle)°").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                LabeledContent("Blur") {
                    Slider(value: $prefs.intensity, in: 0...1)
                    Text("\(Int(prefs.intensity * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                LabeledContent("Darkness") {
                    Slider(value: $prefs.maxDarkness, in: 0...1)
                    Text("\(Int(prefs.maxDarkness * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Text("The effect starts from wherever the lid was resting and is complete at this angle.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset to Defaults") { prefs.resetEffect() }
            }

            Section("Renderer") {
                Picker("Renderer", selection: $prefs.rendererMode) {
                    Text("Auto").tag(RendererMode.auto)
                    Text("Lite").tag(RendererMode.lite)
                    Text("Full").tag(RendererMode.full)
                }
                .pickerStyle(.segmented)
                if screenRecordingGranted {
                    Label("Screen Recording is allowed: Full folds the actual screen content.", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Label("Without Screen Recording only Lite (system blur) is available.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow…") { requestScreenRecording() }
                    }
                }
            }

            Section("Shortcuts") {
                HotKeyRecorderView(title: "Turn the effect on or off", action: .toggleEffect, manager: services.hotKeys)
                HotKeyRecorderView(title: "Back to defaults", action: .resetEffect, manager: services.hotKeys)
                Text("Both work from any app, even while the screen is dark: they hide the effect first, then change the setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { automaticUpdateChecks },
                    set: {
                        automaticUpdateChecks = $0
                        AppUpdater.automaticallyChecksForUpdates = $0
                    }
                ))
                Text("Checks updates.dangkhoabach.vn once a day. Turning this off means updates only happen when you ask for them.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Check Now") { AppUpdater.checkForUpdates() }
                }
            }

            Section("Preview") {
                Toggle("Drive the effect with this slider instead of the lid", isOn: Binding(
                    get: { services.monitor.previewAngle != nil },
                    set: { services.monitor.previewAngle = $0 ? previewAngle : nil }
                ))
                Slider(value: $previewAngle, in: 0...180, step: 1) {
                    Text("Lid angle")
                } minimumValueLabel: { Text("0°") } maximumValueLabel: { Text("180°") }
                .disabled(services.monitor.previewAngle == nil)
                Text("\(Int(previewAngle))°").monospacedDigit().foregroundStyle(.secondary)
                Toggle("Show debug HUD", isOn: $prefs.showDebugHUD)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 720)
        // Sparkle's first-launch prompt can change this after the view was built.
        .onAppear { automaticUpdateChecks = AppUpdater.automaticallyChecksForUpdates }
        .onChange(of: themeRaw) { _, _ in ThemePreference.apply() }
        .onChange(of: previewAngle) { _, angle in if services.monitor.previewAngle != nil { services.monitor.previewAngle = angle } }
        .onDisappear { services.monitor.previewAngle = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }

    /// The system prompt shows only once per app; after that macOS just says
    /// no, so the button opens the Privacy pane instead.
    private func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess()
        if !screenRecordingGranted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                loginItemNeedsApproval = try LoginItemManager.shared.enable()
            } else {
                try LoginItemManager.shared.disable()
                loginItemNeedsApproval = false
            }
            loginItemEnabled = LoginItemManager.shared.isEnabled
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            loginItemEnabled = LoginItemManager.shared.isEnabled
        }
    }
}
