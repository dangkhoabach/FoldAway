import Foundation
import Testing
@testable import FoldAway

@MainActor
@Suite struct AppPreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AppPreferencesTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultValues() {
        let p = AppPreferences(defaults: freshDefaults())
        #expect(p.isEnabled)
        #expect(p.endAngle == 25)
        #expect(p.intensity == 1)
        #expect(p.maxDarkness == 1)
        #expect(p.revealOnOpen)
        #expect(p.rendererMode == .auto)
        #expect(!p.showDebugHUD)
    }

    @Test func changesRoundTripThroughUserDefaults() {
        let d = freshDefaults()
        let p = AppPreferences(defaults: d)
        p.endAngle = 30; p.rendererMode = .lite; p.intensity = 0.5; p.isEnabled = false
        let again = AppPreferences(defaults: d)
        #expect(again.endAngle == 30)
        #expect(again.rendererMode == .lite)
        #expect(again.intensity == 0.5)
        #expect(!again.isEnabled)
    }

    @Test func outOfRangeValuesFallBackToDefaults() {
        let d = freshDefaults()
        d.set(150, forKey: AppPreferences.Keys.endAngle)
        d.set(7.0, forKey: AppPreferences.Keys.intensity)
        let p = AppPreferences(defaults: d)
        #expect(p.endAngle == 25)
        #expect(p.intensity == 1)
    }

    @Test func resetEffectKeepsEnabledAndHUD() {
        let p = AppPreferences(defaults: freshDefaults())
        p.endAngle = 40; p.intensity = 0.2; p.maxDarkness = 0.3; p.rendererMode = .lite
        p.isEnabled = false; p.showDebugHUD = true; p.revealOnOpen = false
        p.resetEffect()
        #expect(p.endAngle == 25)
        #expect(p.intensity == 1)
        #expect(p.maxDarkness == 1)
        #expect(p.rendererMode == .auto)
        #expect(p.revealOnOpen)
        #expect(!p.isEnabled)
        #expect(p.showDebugHUD)
    }
}
