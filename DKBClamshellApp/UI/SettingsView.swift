import SwiftUI

/// Placeholder until Phase 4 (plan F4). Only the language picker is live so
/// the String Catalog wiring can be verified now.
struct SettingsView: View {
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue

    var body: some View {
        Form {
            Picker("Language", selection: $languageRaw) {
                Text("English").tag(AppLocale.en.rawValue)
                Text("Tiếng Việt").tag(AppLocale.vi.rawValue)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 160)
    }
}
