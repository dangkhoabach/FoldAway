import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// A half-resolution ScreenCaptureKit stream of the built-in display,
/// excluding this app's own windows (plan D6/D8). Frames are delivered on
/// SCK's queue; the newest one is kept behind a lock for the renderer to pull
/// on the main thread. `start`/`stop` are idempotent.
final class ScreenCaptureSource: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dangkhoabach.dkb-clamshell.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var starting = false
    private var latestBuffer: CVPixelBuffer?
    /// Called on the main thread whenever a new frame is available.
    var onFrame: (@MainActor () -> Void)?

    var latest: CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latestBuffer
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return stream != nil || starting
    }

    func start(displayID: CGDirectDisplayID) {
        lock.lock()
        guard stream == nil, !starting else { lock.unlock(); return }
        starting = true
        lock.unlock()
        let startedAt = CFAbsoluteTimeGetCurrent()
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
                let config = SCStreamConfiguration()
                // display.width/height are points → 1/2 of the Retina pixel size;
                // the blur doesn't need more (Phase 0.7).
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.queueDepth = 3
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await stream.startCapture()
                lock.withLock { self.stream = stream; starting = false }
                #if DEBUG
                NSLog("capture started in %.0f ms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                #endif
            } catch {
                lock.withLock { starting = false }
                #if DEBUG
                NSLog("capture failed: %@", error.localizedDescription)
                #endif
            }
        }
    }

    func stop() {
        lock.lock()
        let running = stream
        stream = nil
        latestBuffer = nil
        lock.unlock()
        guard let running else { return }
        Task {
            try? await running.stopCapture()
            #if DEBUG
            NSLog("capture stopped")
            #endif
        }
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sampleBuffer.imageBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let status = attachments.first?[.status] as? Int, status != SCFrameStatus.complete.rawValue {
            return
        }
        lock.lock()
        latestBuffer = buffer
        let handler = onFrame
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in handler() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        if self.stream === stream { self.stream = nil }
        lock.unlock()
    }
}
