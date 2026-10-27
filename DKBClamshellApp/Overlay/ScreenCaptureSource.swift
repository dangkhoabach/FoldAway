import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// A half-resolution ScreenCaptureKit stream of the built-in display,
/// excluding this app's own windows. Frames are delivered on
/// SCK's queue; the newest one is kept behind a lock for the renderer to pull
/// on the main thread.
///
/// Most of a cold start (~150–210 ms measured on a Mac15,6) is enumerating shareable
/// content, not starting the stream, so `prepare` does that ahead of time —
/// at launch and again after every `stop` — and `start` only has to call
/// `startCapture` (tens of ms). `start`/`stop` are idempotent.
final class ScreenCaptureSource: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dangkhoabach.dkb-clamshell.capture", qos: .userInteractive)
    private let lock = NSLock()
    private let displayID: CGDirectDisplayID
    private var prepared: SCStream?
    private var running: SCStream?
    private var busy = false
    private var latestBuffer: CVPixelBuffer?
    /// Called on the main thread whenever a new frame is available.
    var onFrame: (@MainActor () -> Void)?

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init()
        prepare()
    }

    var latest: CVPixelBuffer? {
        lock.withLock { latestBuffer }
    }

    var isRunning: Bool {
        lock.withLock { running != nil || busy }
    }

    /// Builds the filter and stream so `start` is quick. Safe to call any time.
    func prepare() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
                let config = SCStreamConfiguration()
                // display.width/height are points → 1/2 of the Retina pixel size;
                // the blur doesn't need more.
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.queueDepth = 3
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                lock.withLock { prepared = stream }
            } catch {
                #if DEBUG
                NSLog("capture prepare failed: %@", error.localizedDescription)
                #endif
            }
        }
    }

    func start() {
        let stream: SCStream? = lock.withLock {
            guard running == nil, !busy, let stream = prepared else { return nil }
            busy = true
            prepared = nil
            return stream
        }
        guard let stream else {
            if !isRunning { prepare() }      // nothing prepared yet: get one ready for next time
            return
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        Task {
            do {
                try await stream.startCapture()
                lock.withLock { running = stream; busy = false }
                #if DEBUG
                NSLog("capture started in %.0f ms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                #endif
            } catch {
                lock.withLock { busy = false }
                #if DEBUG
                NSLog("capture failed: %@", error.localizedDescription)
                #endif
                prepare()
            }
        }
    }

    func stop() {
        let stream: SCStream? = lock.withLock {
            let s = running
            running = nil
            latestBuffer = nil
            return s
        }
        guard let stream else { return }
        Task {
            try? await stream.stopCapture()
            #if DEBUG
            NSLog("capture stopped")
            #endif
            prepare()
        }
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sampleBuffer.imageBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let status = attachments.first?[.status] as? Int, status != SCFrameStatus.complete.rawValue {
            return
        }
        let (first, handler): (Bool, (@MainActor () -> Void)?) = lock.withLock {
            let first = latestBuffer == nil
            latestBuffer = buffer
            return (first, onFrame)
        }
        #if DEBUG
        if first { NSLog("capture: first frame") }
        #endif
        guard let handler else { return }
        Task { @MainActor in handler() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { if running === stream { running = nil } }
    }
}
