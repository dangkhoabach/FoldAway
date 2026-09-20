import SwiftUI

/// Phase 3 slice of Settings (plan D17): the Preview slider and the debug
/// HUD, plus the language picker. The rest of the form lands in Phase 4.
struct SettingsView: View {
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue
    @State private var previewOn = false
    @State private var previewAngle = 180.0
    private let services = AppServices.shared

    var body: some View {
        @Bindable var prefs = services.preferences
        Form {
            Section("Preview") {
                Toggle("Drive the effect with this slider instead of the lid", isOn: $previewOn)
                Slider(value: $previewAngle, in: 0...180, step: 1) {
                    Text("Lid angle")
                } minimumValueLabel: { Text("0°") } maximumValueLabel: { Text("180°") }
                .disabled(!previewOn)
                Text("\(Int(previewAngle))°").monospacedDigit().foregroundStyle(.secondary)
                Toggle("Show debug HUD", isOn: $prefs.showDebugHUD)
            }
            Section("Language") {
                Picker("Language", selection: $languageRaw) {
                    Text("English").tag(AppLocale.en.rawValue)
                    Text("Tiếng Việt").tag(AppLocale.vi.rawValue)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 320)
        .onChange(of: previewOn) { _, on in services.monitor.previewAngle = on ? previewAngle : nil }
        .onChange(of: previewAngle) { _, angle in if previewOn { services.monitor.previewAngle = angle } }
        .onDisappear { previewOn = false; services.monitor.previewAngle = nil }
    }
}
