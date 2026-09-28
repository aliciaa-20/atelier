import CoreMedia
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case applicationUnavailable

    var errorDescription: String? {
        "Atelier could not safely exclude its own windows from screen capture. Try enabling the bend effect again."
    }
}

/// Adapted from IuCC123/BendMac's `DesktopCapture.swift` (MIT). Invariant 2
/// from CLAUDE.md doesn't apply here (there's no other app to avoid
/// launching), but the same "don't act until the OS has actually caught up
/// with us" caution does: never start an unfiltered stream before
/// ScreenCaptureKit has discovered this process's own windows, or the
/// filter below excludes nothing.
final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: FrameStore
    @MainActor private var stream: SCStream?
    @MainActor private var config: SCStreamConfiguration?
    private let queue = DispatchQueue(label: "atelier.bendEffect.capture", qos: .userInteractive)
    // Assigned once from `BendEffectController.init` (main actor) before
    // `start()` is ever called, then only read from a `Task { @MainActor }`
    // hop -- same single-assignment-before-concurrent-use convention the
    // original relied on.
    nonisolated(unsafe) var onError: ((Error) -> Void)?
    nonisolated(unsafe) var onFirstFrame: (() -> Void)?
    private let countLock = NSLock()
    // `nonisolated`: guarded by `countLock`, not the main actor -- touched
    // from both the `@MainActor` start/stop methods and the capture-queue
    // delegate callbacks below. This project's whole-module default-
    // MainActor isolation would otherwise make the delegate callbacks
    // MainActor-isolated even though ScreenCaptureKit actually invokes them
    // on `queue`, the same mismatch fixed in `LidSensor`.
    private nonisolated(unsafe) var count = 0
    private nonisolated(unsafe) var outputStream: SCStream?
    @MainActor private var generation = 0
    @MainActor private var desiredBending = false
    @MainActor private var updatingRate = false
    nonisolated var frameCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return count
    }
    init(frames: FrameStore) { self.frames = frames }

    @MainActor func start(displayID: CGDirectDisplayID) async throws {
        generation += 1
        let request = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard request == generation else { throw CancellationError() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "The built-in display is unavailable.", code: 1)
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // A login launch may have no on-screen windows. Never start an unfiltered
        // stream if ScreenCaptureKit has not discovered this process yet.
        guard !ownApp.isEmpty else { throw CaptureError.applicationUnavailable }
        // Exclude our entire process, including windows shown after capture starts.
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        // Use the display mode's backing resolution for Retina capture.
        let mode = CGDisplayCopyDisplayMode(displayID)
        config.width = mode?.pixelWidth ?? CGDisplayPixelsWide(displayID)
        config.height = mode?.pixelHeight ?? CGDisplayPixelsHigh(displayID)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        self.config = config
        desiredBending = false
        acceptOutput(from: stream)
        do {
            try await stream.startCapture()
            guard request == generation else {
                try? await stream.stopCapture()
                throw CancellationError()
            }
        } catch {
            if self.stream === stream {
                self.stream = nil
                self.config = nil
                acceptOutput(from: nil)
            }
            throw error
        }
    }
    @MainActor func setBending(_ active: Bool) async {
        desiredBending = active
        guard !updatingRate else { return }
        updatingRate = true
        defer { updatingRate = false }
        while let stream, let config {
            let requested = desiredBending
            config.minimumFrameInterval = CMTime(value: 1, timescale: requested ? 60 : 5)
            do { try await stream.updateConfiguration(config) } catch {
                if self.stream === stream {
                    onError?(error)
                    return
                }
                // An obsolete stream must not discard a newer stream's pending rate change.
                continue
            }
            if self.stream === stream && requested == desiredBending { return }
        }
    }
    @MainActor func stop() async {
        generation += 1
        let old = stream
        stream = nil
        config = nil
        acceptOutput(from: nil)
        try? await old?.stopCapture()
    }
    private nonisolated func acceptOutput(from stream: SCStream?) {
        countLock.lock()
        defer { countLock.unlock() }
        outputStream = stream
        frames.clear()
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        // `SCStream` isn't `Sendable`; send its identity across the actor
        // hop instead of the object itself.
        let streamID = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == streamID else { return }
            self.onError?(error)
        }
    }
    nonisolated func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: raw) == .complete,
            let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        countLock.lock()
        defer { countLock.unlock() }
        guard outputStream === stream else { return }
        let firstFrame = frames.get() == nil
        frames.put(pixelBuffer, displayTime: attachments.first?[.displayTime] as? UInt64 ?? 0)
        if firstFrame {
            // Same identity-across-the-hop reasoning as `didStopWithError`.
            let streamID = ObjectIdentifier(stream)
            Task { @MainActor [weak self] in
                guard let self, self.stream.map(ObjectIdentifier.init) == streamID else { return }
                self.onFirstFrame?()
            }
        }
        count += 1
    }
}
