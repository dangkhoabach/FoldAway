import AppKit
import MetalKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Plan D7 overlay window: full built-in screen, above everything, ignores mouse, not captured.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
    }
}

struct EffectParams {
    var progress: Double
    var blur: Double { 35 * progress }                       // px at half-res
    var darkness: Double { min(1, 1.6 * progress) }
    var tilt: Double { 0.06 * progress }                     // fraction of width pulled in at the top
    var scaleY: Double { 1 - 0.08 * progress }
}

/// Lite: NSVisualEffectView alpha ramp + darkening gradient. No capture, no permission.
final class LiteView: NSView {
    private let blur = NSVisualEffectView()
    private let grad = CAGradientLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        blur.material = .fullScreenUI; blur.blendingMode = .behindWindow; blur.state = .active
        blur.frame = bounds; blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        let g = NSView(frame: bounds); g.autoresizingMask = [.width, .height]; g.wantsLayer = true
        grad.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.3).cgColor]
        grad.startPoint = CGPoint(x: 0.5, y: 1); grad.endPoint = CGPoint(x: 0.5, y: 0)   // top → bottom (hinge)
        grad.frame = bounds; g.layer = grad
        addSubview(g)
        apply(EffectParams(progress: 0))
    }
    required init?(coder: NSCoder) { fatalError() }
    func apply(_ p: EffectParams) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        blur.alphaValue = min(1, p.progress * 1.5)
        grad.opacity = Float(p.darkness)
        CATransaction.commit()
    }
}

/// Full: captured half-res frame → CI perspective + blur + gradient → MTKView.
final class FullView: MTKView {
    private let ciContext: CIContext
    private let queue: MTLCommandQueue
    var params = EffectParams(progress: 0)
    var frame_: CVPixelBuffer?
    private(set) var drawCount = 0

    init(frame: NSRect) {
        let dev = MTLCreateSystemDefaultDevice()!
        queue = dev.makeCommandQueue()!
        ciContext = CIContext(mtlDevice: dev, options: [.cacheIntermediates: false])
        super.init(frame: frame, device: dev)
        framebufferOnly = false
        isPaused = true; enableSetNeedsDisplay = false
        autoResizeDrawable = false
        layer?.isOpaque = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }
    required init(coder: NSCoder) { fatalError() }

    func render() {
        guard let pb = frame_, let drawable = currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        let w = CGFloat(CVPixelBufferGetWidth(pb)), h = CGFloat(CVPixelBufferGetHeight(pb))
        if drawableSize != CGSize(width: w, height: h) { drawableSize = CGSize(width: w, height: h) }
        var img = CIImage(cvPixelBuffer: pb)
        let p = params
        if p.progress > 0 {
            // Tilt around the bottom edge (hinge): bottom corners fixed, top corners pulled in and down.
            let inset = w * p.tilt, top = h * p.scaleY
            let persp = CIFilter.perspectiveTransform()
            persp.inputImage = img
            persp.bottomLeft = CGPoint(x: 0, y: 0); persp.bottomRight = CGPoint(x: w, y: 0)
            persp.topLeft = CGPoint(x: inset, y: top); persp.topRight = CGPoint(x: w - inset, y: top)
            img = persp.outputImage ?? img
            if p.blur > 0.5 {
                img = img.clampedToExtent().applyingGaussianBlur(sigma: p.blur).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            }
            let g = CIFilter.linearGradient()
            g.point0 = CGPoint(x: 0, y: h); g.point1 = CGPoint(x: 0, y: 0)
            g.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: p.darkness)
            g.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: p.darkness * 0.3)
            if let go = g.outputImage { img = go.cropped(to: CGRect(x: 0, y: 0, width: w, height: h)).composited(over: img) }
        }
        ciContext.render(img, to: drawable.texture, commandBuffer: cb, bounds: CGRect(x: 0, y: 0, width: w, height: h), colorSpace: CGColorSpaceCreateDeviceRGB())
        cb.present(drawable); cb.commit()
        drawCount += 1
    }
}
