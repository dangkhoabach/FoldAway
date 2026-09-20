import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

/// Half-resolution SCStream of the built-in display, excluding this app's own windows.
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "capture", qos: .userInteractive)
    private(set) var latest: CVPixelBuffer?
    var onFrame: ((CVPixelBuffer) -> Void)?
    private var firstFrameAt: CFAbsoluteTime?
    private var startedAt: CFAbsoluteTime = 0
    private(set) var frameCount = 0

    static func builtinDisplayID() -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    /// Returns (startCapture await ms, first-frame ms) — the numbers for plan 0.3.
    @discardableResult
    func start() async throws -> (startMs: Double, firstFrameMs: Double) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = Self.builtinDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw NSError(domain: "PoC", code: 1, userInfo: [NSLocalizedDescriptionKey: "built-in display not shareable"])
        }
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        // display.width/height are points → capturing at that pixel size = 1/2 of the Retina resolution.
        cfg.width = display.width; cfg.height = display.height
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.queueDepth = 3
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        firstFrameAt = nil; frameCount = 0; startedAt = t0
        try await s.startCapture()
        let t1 = CFAbsoluteTimeGetCurrent()
        stream = s
        // Wait (max 2 s) for the first frame.
        while firstFrameAt == nil, CFAbsoluteTimeGetCurrent() - t0 < 2 { try await Task.sleep(nanoseconds: 2_000_000) }
        let ff = firstFrameAt.map { ($0 - t0) * 1000 } ?? -1
        return ((t1 - t0) * 1000, ff)
    }

    func stop() async {
        guard let s = stream else { return }
        stream = nil
        try? await s.stopCapture()
        latest = nil
    }

    var isRunning: Bool { stream != nil }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = sb.imageBuffer else { return }
        if let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let st = att.first?[.status] as? Int, st != SCFrameStatus.complete.rawValue { return }
        if firstFrameAt == nil { firstFrameAt = CFAbsoluteTimeGetCurrent() }
        frameCount += 1
        latest = pb
        onFrame?(pb)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.w("SCStream stopped: \(error.localizedDescription)")
        self.stream = nil
    }
}
