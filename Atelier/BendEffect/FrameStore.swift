import CoreVideo
import Foundation

/// Adapted from IuCC123/BendMac's `Renderer.swift` (MIT), extracted into
/// its own file since both `DesktopCapture` and `BendRenderer` depend on
/// it. Latest-frame mailbox between the capture-queue callback and the
/// Metal draw callback -- `CVPixelBuffer` isn't `Sendable`, so this is a
/// lock-guarded box, same reasoning as `CameraMirrorSource.SessionBox`.
final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var displayTime: UInt64 = 0

    func put(_ frame: CVPixelBuffer, displayTime: UInt64 = 0) {
        lock.lock()
        latest = frame
        self.displayTime = displayTime
        lock.unlock()
    }

    func get() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    var hasFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return latest != nil
    }

    func clear() {
        lock.lock()
        latest = nil
        displayTime = 0
        lock.unlock()
    }
}
