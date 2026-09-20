import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import DKBClamshellCore
import MetalKit

/// The Duo look (plan D6): the captured picture is re-projected with
/// `FoldProjection` so it seems to stay where the screen was while the lid
/// folds under it; the further a panel pixel is from the hinge — the wider
/// the gap between the glass and the picture — the more it is blurred and
/// darkened; the last stretch of the close fades everything to black.
/// Until the first frame arrives (Phase 0.3: up to ~212 ms after `prepare`)
/// the Lite renderer stands in so the effect starts on time (plan D8).
@MainActor
final class FullEffectRenderer: EffectRendering {
    private let container = NSView()
    private let metalView: MTKView
    private let fallback: LiteEffectRenderer
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let capture = ScreenCaptureSource()
    private let displayID: CGDirectDisplayID
    private var params = EffectParameters(progress: 0, delta: 0)
    private var lastDrawnFrame: CVPixelBuffer?
    private var lastDrawnParams: EffectParameters?

    var view: NSView { container }

    init?(size: CGSize, displayID: CGDirectDisplayID) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.displayID = displayID
        commandQueue = queue
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        metalView = MTKView(frame: NSRect(origin: .zero, size: size), device: device)
        metalView.framebufferOnly = false
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        metalView.autoResizeDrawable = false
        metalView.layer?.isOpaque = false
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.autoresizingMask = [.width, .height]
        fallback = LiteEffectRenderer(size: size)
        fallback.view.autoresizingMask = [.width, .height]
        container.frame = NSRect(origin: .zero, size: size)
        container.addSubview(fallback.view)
        container.addSubview(metalView)
        metalView.isHidden = true
        capture.onFrame = { [weak self] in self?.frameArrived() }
    }

    func prepare() {
        capture.start(displayID: displayID)
    }

    func update(_ params: EffectParameters) {
        self.params = params
        guard let frame = capture.latest else {
            fallback.update(params)
            return
        }
        if metalView.isHidden {
            metalView.isHidden = false
            fallback.view.isHidden = true
        }
        // The display link calls this 60×/s; the GPU work is skipped when
        // neither the picture nor the parameters changed since the last draw.
        if params == lastDrawnParams, frame === lastDrawnFrame { return }
        draw(frame)
    }

    func stop() {
        capture.stop()
        lastDrawnFrame = nil
        lastDrawnParams = nil
        metalView.isHidden = true
        fallback.view.isHidden = false
        fallback.update(EffectParameters(progress: 0, delta: 0))
    }

    private func frameArrived() {
        // A new frame between two `update`s: redraw with the current params so
        // the picture stays live (and the first frame takes over from the fallback).
        update(params)
    }

    private func draw(_ frame: CVPixelBuffer) {
        guard let drawable = metalView.currentDrawable, let commands = commandQueue.makeCommandBuffer() else { return }
        let w = CGFloat(CVPixelBufferGetWidth(frame)), h = CGFloat(CVPixelBufferGetHeight(frame))
        let size = CGSize(width: w, height: h)
        if metalView.drawableSize != size { metalView.drawableSize = size }
        let bounds = CGRect(origin: .zero, size: size)
        let p = params

        // Core Image's origin is bottom-left, which is the hinge edge.
        var picture = CIImage(cvPixelBuffer: frame)

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

        context.render(image, to: drawable.texture, commandBuffer: commands, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        commands.present(drawable)
        commands.commit()
        lastDrawnFrame = frame
        lastDrawnParams = p
    }
}
