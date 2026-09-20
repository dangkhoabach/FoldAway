import Foundation
import Testing
@testable import DKB_Clamshell

@MainActor
@Suite struct AppPreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "AppPreferencesTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultsMatchThePlan() {
        let p = AppPreferences(defaults: freshDefaults())
        #expect(p.isEnabled)
        #expect(p.startAngle == 85)
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
        p.startAngle = 100; p.endAngle = 30; p.rendererMode = .lite; p.intensity = 0.5; p.isEnabled = false
        let again = AppPreferences(defaults: d)
        #expect(again.startAngle == 100)
        #expect(again.endAngle == 30)
        #expect(again.rendererMode == .lite)
        #expect(again.intensity == 0.5)
        #expect(!again.isEnabled)
    }

    @Test func invertedOrOutOfRangeAnglesFallBackToDefaults() {
        let d = freshDefaults()
        d.set(20, forKey: AppPreferences.Keys.startAngle)
        d.set(80, forKey: AppPreferences.Keys.endAngle)
        d.set(7.0, forKey: AppPreferences.Keys.intensity)
        let p = AppPreferences(defaults: d)
        #expect(p.startAngle == 85)
        #expect(p.endAngle == 25)
        #expect(p.intensity == 1)
    }
}
