import AppKit
import Testing
@testable import FoldAway

@MainActor
@Suite struct AboutWindowTests {
    @Test func readsTheVersionAndTheReleaseDay() throws {
        let info = AboutInfo(info: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "1.2.0", "AppReleaseDate": "2026-11-14"])
        #expect(info.versionText == "1.2.0")
        let day = try #require(info.releaseDay)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 14)
    }

    @Test func showsTheBuildOnlyWhenItDiffers() {
        #expect(AboutInfo(info: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "57"]).versionText == "1.2.0 (57)")
        #expect(AboutInfo(info: ["CFBundleShortVersionString": "1.2.0"]).versionText == "1.2.0")
    }

    @Test func leavesTheDateOutWhenThereIsNone() {
        #expect(AboutInfo(info: ["AppReleaseDate": "soon"]).releaseDay == nil)
        #expect(AboutInfo(info: [:]).releaseDay == nil)
    }

    /// The app's own Info.plist carries the date release.sh writes.
    @Test func theAppHasAReleaseDate() {
        #expect(AboutInfo(info: Bundle.main.infoDictionary ?? [:]).releaseDay != nil)
    }

    /// The status item shows the state without opening the panel.
    @Test func theIconFollowsTheState() {
        #expect(MenuBarPanelView.iconSymbol(status: .running, enabled: true) == "laptopcomputer")
        #expect(MenuBarPanelView.iconSymbol(status: .running, enabled: false) == "laptopcomputer.slash")
        #expect(MenuBarPanelView.iconSymbol(status: .sensorError("x"), enabled: true) == "exclamationmark.triangle")
    }

    @Test func theWindowShowsAndComesBackAsOne() throws {
        AboutWindow.show()
        AboutWindow.show()
        let title = String(localized: "About FoldAway", bundle: AppLocale.bundle)
        let windows = NSApp.windows.filter { $0.isVisible && $0.title == title }
        #expect(windows.count == 1)
        windows.forEach { $0.close() }
    }
}
