import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import DKBClamshellCore
import Metal
import QuartzCore

/// The Duo look (plan D6): the captured picture is re-projected with
/// `FoldProjection` so it seems to stay where the screen was while the lid
/// folds under it; the further a panel pixel is from the hinge — the wider
/// the gap between the glass and the picture — the more it is blurred and
/// darkened; the last stretch of the close fades everything to black.
/// Until the first frame arrives (a few tens of ms with the stream prepared
/// ahead of time) only the shade is drawn, so the effect starts on time and
/// the hand-over adds the stretch and blur without a brightness jump.
@MainActor
final class FullEffectRenderer: EffectRendering {
    private let container = NSView()
    /// A bare `CAMetalLayer`, not `MTKView`: this renderer draws from the
    /// display link on its own schedule, and `MTKView.currentDrawable` is
    /// cached until the view's own `draw()` ends — presenting it again from
    /// outside that cycle shows nothing (the picture froze after the first
    /// frame, then went black once the texture was overwritten in place).
    private let metalView = NSView()
    private let metalLayer = CAMetalLayer()
    private let shadeView = NSView()
    private let shade = CAGradientLayer()
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let capture: ScreenCaptureSource
    private var params = EffectParameters(progress: 0, delta: 0)
    private var lastDrawnFrame: CVPixelBuffer?
    private var lastDrawnParams: EffectParameters?
    private var needsDraw = false

    var view: NSView { container }

    init?(size: CGSize, displayID: CGDirectDisplayID) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        capture = ScreenCaptureSource(displayID: displayID)
        commandQueue = queue
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.contentsGravity = .resize
        metalView.frame = NSRect(origin: .zero, size: size)
        metalView.wantsLayer = true
        metalView.layer = metalLayer
        metalView.autoresizingMask = [.width, .height]
        shadeView.frame = NSRect(origin: .zero, size: size)
        shadeView.autoresizingMask = [.width, .height]
        shadeView.wantsLayer = true
        shade.frame = shadeView.bounds
        shadeView.layer = shade
        container.frame = NSRect(origin: .zero, size: size)
        container.addSubview(shadeView)
        container.addSubview(metalView)
        metalView.isHidden = true
        capture.onFrame = { [weak self] in self?.frameArrived() }
    }

    func prepare() {
        capture.start()
    }

    func update(_ params: EffectParameters) {
        self.params = params
        needsDraw = true
        if capture.latest == nil { applyShade(params) }
    }

    private func applyShade(_ p: EffectParameters) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let far: CGFloat = p.direction == .topDown ? 1 : 0   // far edge → hinge
        shade.startPoint = CGPoint(x: 0.5, y: far)
        shade.endPoint = CGPoint(x: 0.5, y: 1 - far)
        shade.colors = [NSColor.black.withAlphaComponent(max(p.farDarkness, p.fade)).cgColor,
                        NSColor.black.withAlphaComponent(max(p.hingeDarkness, p.fade)).cgColor]
        CATransaction.commit()
    }

    func render() {
        guard needsDraw, let frame = capture.latest else { return }
        if metalView.isHidden {
            metalView.isHidden = false
            shadeView.isHidden = true
            #if DEBUG
            NSLog("full renderer: first frame, taking over from the shade")
            #endif
        }
        needsDraw = false
        // Skip the GPU work when neither the picture nor the parameters changed.
        if params == lastDrawnParams, frame === lastDrawnFrame { return }
        draw(frame)
    }

    func stop() {
        capture.stop()
        lastDrawnFrame = nil
        lastDrawnParams = nil
        metalView.isHidden = true
        shadeView.isHidden = false
        applyShade(EffectParameters(progress: 0, delta: 0))
    }

    private func frameArrived() {
        // Picked up by the next `render()`; never draw from here.
        needsDraw = true
    }

    #if DEBUG
    private var drawCount = 0, noDrawableCount = 0
    #endif

    private func draw(_ frame: CVPixelBuffer) {
        let w = CGFloat(CVPixelBufferGetWidth(frame)), h = CGFloat(CVPixelBufferGetHeight(frame))
        let size = CGSize(width: w, height: h)
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        guard let drawable = metalLayer.nextDrawable(), let commands = commandQueue.makeCommandBuffer() else {
            #if DEBUG
            noDrawableCount += 1
            if noDrawableCount % 30 == 1 { NSLog("full renderer: no drawable (%d so far)", noDrawableCount) }
            #endif
            return
        }
        #if DEBUG
        drawCount += 1
        if drawCount % 30 == 1 { NSLog("full renderer: draw #%d δ=%.1f fade=%.2f", drawCount, params.delta, params.fade) }
        #endif
        let bounds = CGRect(origin: .zero, size: size)
        let p = params

        // Core Image's origin is bottom-left, which is the hinge edge. The
        // pipeline below always folds the top edge away; `bottomUp` is the
        // same pipeline on a vertically flipped picture, flipped back at the end.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        var picture = CIImage(cvPixelBuffer: frame)
        if p.direction == .bottomUp { picture = picture.transformed(by: flip) }

        // 1. Re-project: the picture stays put, the panel folds under it.
        let projection = FoldProjection(width: w, height: h, delta: p.delta)
        let perspective = CIFilter.perspectiveTransform()
        perspective.inputImage = picture
        perspective.bottomLeft = CGPoint(x: projection.bottomLeft.x, y: projection.bottomLeft.y)
        perspective.bottomRight = CGPoint(x: projection.bottomRight.x, y: projection.bottomRight.y)
        perspective.topLeft = CGPoint(x: projection.topLeft.x, y: projection.topLeft.y)
        perspective.topRight = CGPoint(x: projection.topRight.x, y: projection.topRight.y)
        picture = (perspective.outputImage ?? picture).cropped(to: bounds)

        // 2. Frost: blur grows from nothing at the hinge to `farBlurRadius` at the top.
        if p.farBlurRadius > 0.5 {
            let ramp = CIFilter.linearGradient()
            ramp.point0 = CGPoint(x: 0, y: 0)
            ramp.point1 = CGPoint(x: 0, y: h)
            ramp.color0 = .black
            ramp.color1 = .white
            let blur = CIFilter.maskedVariableBlur()
            blur.inputImage = picture.clampedToExtent()
            blur.mask = ramp.outputImage?.cropped(to: bounds)
            blur.radius = Float(p.farBlurRadius)
            picture = (blur.outputImage ?? picture).cropped(to: bounds)
        }

        // 3. Shade: light falls off with the gap, hinge → far edge.
        let shade = CIFilter.linearGradient()
        shade.point0 = CGPoint(x: 0, y: 0)
        shade.point1 = CGPoint(x: 0, y: h)
        shade.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: p.hingeDarkness)
        shade.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: p.farDarkness)
        if let shadeImage = shade.outputImage?.cropped(to: bounds) {
            picture = shadeImage.composited(over: picture)
        }

        // 4. Whatever the narrowed picture no longer covers is black, and the
        //    whole thing fades to black at the end of the close.
        let backdropAlpha = max(p.fade, min(1, p.delta / 10))
        var image = picture.composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: backdropAlpha)).cropped(to: bounds))
        if p.fade > 0 {
            image = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: p.fade)).cropped(to: bounds).composited(over: image)
        }
        if p.direction == .bottomUp { image = image.transformed(by: flip) }

        context.render(image, to: drawable.texture, commandBuffer: commands, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        commands.present(drawable)
        commands.commit()
        lastDrawnFrame = frame
        lastDrawnParams = p
    }
}
