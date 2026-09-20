import Foundation

/// The iPhone Duo principle, applied to a lid: the picture stays where the
/// screen *was* (the plane at the resting angle, P0) while the physical panel
/// (P1) rotates down by `delta` around the hinge. For every panel point, the
/// ray from the viewer's eye through it decides which picture point shows
/// there — a planar homography with the hinge line fixed.
///
/// Side view, hinge at the origin, the screen's up direction is y, the
/// viewer sits in front at x = D, eye height `eyeHeight` above the hinge:
///
///     panel point at distance s from the hinge, rotated by δ:  (s·sin δ, s·cos δ)
///     ray from E = (D, Ey) through it meets P0 (x = 0) at
///         y0 = s·(D·cos δ − Ey·sin δ) / (D − s·sin δ)
///     inverting: s = D·y0 / (D·cos δ − Ey·sin δ + y0·sin δ)
///     and the lateral coordinate scales by (D·cos δ − Ey·sin δ) / (D·cos δ − Ey·sin δ + y0·sin δ)
///
/// The same mapping as ashtree74/MacDuo's `x₁ = K·x₀/(K − b·y₀)`,
/// `y₁ = c·y₀/(K − b·y₀)`. At δ = 0 it is the identity. As the lid folds
/// toward the viewer the panel becomes a window sliding down over a picture
/// that stays put behind it: on the panel that is a *stretch* — the far edge
/// of the picture runs off the top (magnified) while narrowing sideways, and
/// the hinge edge never moves. When `tan δ` approaches `D / Ey` the rays run
/// parallel to the panel, so δ is clamped just short of that.
public struct FoldProjection: Equatable, Sendable {
    /// Eye distance in front of the resting screen, in screen heights.
    public static let eyeDistance = 2.6
    /// Eye height above the hinge, in screen heights (screen centre + 0.5).
    public static let eyeHeight = 1.0
    /// Exact geometry (1.0) is harsh; MacDuo ships 0.6 and so do we.
    public static let strength = 0.6

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public var bottomLeft: Point
    public var bottomRight: Point
    public var topLeft: Point
    public var topRight: Point

    /// Where the four corners of the picture (width × height, hinge along the
    /// bottom edge, origin bottom-left) land on the panel folded by `delta`
    /// degrees below the resting angle.
    public init(width: Double, height: Double, delta: Double) {
        let d = Self.eyeDistance * height
        let ey = Self.eyeHeight * height
        let limit = atan2(d, ey) * 180 / .pi - 4
        let rad = min(max(0, delta * Self.strength), limit) * .pi / 180
        let s = sin(rad), c = cos(rad)
        let k = d * c - ey * s                      // > 0 below the limit
        func map(_ x0: Double, _ y0: Double) -> Point {
            let denominator = k + y0 * s
            return Point(x: width / 2 + (x0 - width / 2) * k / denominator, y: d * y0 / denominator)
        }
        bottomLeft = map(0, 0)
        bottomRight = map(width, 0)
        topLeft = map(0, height)
        topRight = map(width, height)
    }

    /// Vertical magnification at the far edge: 1 at rest, growing with the fold.
    public func stretch(height: Double) -> Double {
        topLeft.y / height
    }
}
