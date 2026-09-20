import Foundation

/// What the renderers draw for a given fold (plan §5.3). Blur and darkness are
/// *graded*: nothing at the hinge, strongest at the far edge, because that is
/// where the picture has fallen furthest behind the glass. `progress` (0…1
/// over the whole close) drives the final fade to black.
public struct EffectParameters: Equatable, Sendable {
    /// Gaussian radius at the far edge when fully folded, in captured pixels
    /// (half resolution → ~120 pt on screen, MacDuo's default).
    public static let maxBlur = 40.0
    /// The fold, in degrees below rest, at which blur and darkness saturate.
    public static let saturationDelta = 70.0

    public var progress: Double
    /// Degrees below the resting angle (already ≥ 0).
    public var delta: Double
    /// Blur radius at the far edge; the mask ramps it from 0 at the hinge.
    public var farBlurRadius: Double
    /// 0 = untouched, 1 = black — at the far edge; the hinge edge keeps
    /// `hingeDarkness`.
    public var farDarkness: Double
    public var hingeDarkness: Double
    /// Whole-screen fade to black at the end of the close.
    public var fade: Double

    public init(progress: Double, delta: Double, intensity: Double = 1, maxDarkness: Double = 1) {
        let p = max(0, min(1, progress))
        self.progress = p
        self.delta = max(0, delta)
        let fold = min(1, self.delta / Self.saturationDelta)
        // Ease in: the first degrees are about the picture staying put, the
        // frost and shade arrive as the gap opens up.
        let eased = fold * fold * (3 - 2 * fold)
        farBlurRadius = Self.maxBlur * intensity * eased
        farDarkness = min(1, eased * 1.2) * maxDarkness
        hingeDarkness = 0.25 * eased * maxDarkness
        // Black well before the lid is shut, but only in the last stretch.
        fade = max(0, (p - 0.65) / 0.25).clamped01() * maxDarkness
    }
}

private extension Double {
    func clamped01() -> Double { Swift.max(0, Swift.min(1, self)) }
}
