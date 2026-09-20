import SwiftUI

@main
struct DKBClamshellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue

    private var appLocale: AppLocale {
        AppLocale(rawValue: languageRaw) ?? .systemDefault
    }

    var body: some Scene {
        // Menu bar only (plan D4): the extra is the app's face, Settings is
        // the only window.
        MenuBarExtra {
            MenuBarContentView()
                .environment(\.locale, appLocale.locale)
        } label: {
            Image(systemName: "laptopcomputer")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(\.locale, appLocale.locale)
        }
    }
}
