import SwiftUI

@main
struct FoldAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue

    private var appLocale: AppLocale {
        AppLocale(rawValue: languageRaw) ?? .systemDefault
    }

    var body: some Scene {
        // Menu bar only: the status item (`StatusBarController`) is the
        // app's face, Settings is the only window.
        Settings {
            SettingsView()
                .environment(\.locale, appLocale.locale)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FoldAway") { AboutWindow.show() }
            }
        }
    }
}
