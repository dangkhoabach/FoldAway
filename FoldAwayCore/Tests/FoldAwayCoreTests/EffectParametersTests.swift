import Testing
@testable import FoldAwayCore

@Suite struct EffectParametersTests {
    @Test func atRestNothingIsDrawn() {
        let p = EffectParameters(progress: 0, delta: 0)
        #expect(p.farBlurRadius == 0)
        #expect(p.farDarkness == 0)
        #expect(p.hingeDarkness == 0)
        #expect(p.fade == 0)
    }

    @Test func blurAndDarknessEaseInWithTheFoldAndSaturate() {
        let early = EffectParameters(progress: 0.1, delta: 10)
        #expect(early.farBlurRadius < EffectParameters.maxBlur * 0.1)     // gentler than linear at first
        let mid = EffectParameters(progress: 0.3, delta: 35)
        #expect(abs(mid.farBlurRadius - EffectParameters.maxBlur / 2) < 1e-9)
        #expect(abs(mid.farDarkness - 0.6) < 1e-9)
        #expect(mid.hingeDarkness < mid.farDarkness)
        let far = EffectParameters(progress: 0.5, delta: 90)
        #expect(far.farBlurRadius == EffectParameters.maxBlur)
        #expect(far.farDarkness == 1)
    }

    @Test func fadeToBlackOnlyInTheLastStretch() {
        #expect(EffectParameters(progress: 0.6, delta: 50).fade == 0)
        #expect(abs(EffectParameters(progress: 0.775, delta: 70).fade - 0.5) < 1e-9)
        #expect(EffectParameters(progress: 0.9, delta: 80).fade == 1)
    }

    @Test func knobsScaleBlurAndDarkness() {
        let p = EffectParameters(progress: 1, delta: 90, intensity: 0.5, maxDarkness: 0.8)
        #expect(p.farBlurRadius == EffectParameters.maxBlur / 2)
        #expect(p.farDarkness == 0.8)
        #expect(p.fade == 0.8)
    }

    @Test func inputsAreClamped() {
        let p = EffectParameters(progress: 1.7, delta: -5)
        #expect(p.progress == 1)
        #expect(p.delta == 0)
    }
}
