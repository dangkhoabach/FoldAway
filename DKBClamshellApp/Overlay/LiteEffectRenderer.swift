import AppKit
import DKBClamshellCore

/// No capture, no permission: a system blur layer that fades in, under a
/// darkening gradient that is heaviest at the top and lighter at the hinge
/// (plan §3.1 "Lite"). It cannot tilt or shrink the content.
@MainActor
final class LiteEffectRenderer: EffectRendering {
    let view = NSView()
    private let blur = NSVisualEffectView()
    private let gradient = CAGradientLayer()

    init(size: CGSize) {
        let bounds = NSRect(origin: .zero, size: size)
        view.frame = bounds
        view.wantsLayer = true

        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.frame = bounds
        blur.autoresizingMask = [.width, .height]
        view.addSubview(blur)

        let shade = NSView(frame: bounds)
        shade.autoresizingMask = [.width, .height]
        shade.wantsLayer = true
        gradient.frame = bounds
        shade.layer = gradient
        view.addSubview(shade)

        update(EffectParameters(progress: 0, delta: 0))
    }

    func prepare() {}

    func update(_ params: EffectParameters) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fold = params.farBlurRadius / (EffectParameters.maxBlur * max(0.01, 1))   // 0…1 over the fold
        blur.alphaValue = min(1, fold * 1.5)
        // Far edge → hinge: top of the screen down, or mirrored.
        let far: CGFloat = params.direction == .topDown ? 1 : 0
        gradient.startPoint = CGPoint(x: 0.5, y: far)
        gradient.endPoint = CGPoint(x: 0.5, y: 1 - far)
        gradient.colors = [NSColor.black.withAlphaComponent(max(params.farDarkness, params.fade)).cgColor,
                           NSColor.black.withAlphaComponent(max(params.hingeDarkness, params.fade)).cgColor]
        gradient.opacity = 1
        CATransaction.commit()
    }

    func render() {}

    func stop() {}
}
