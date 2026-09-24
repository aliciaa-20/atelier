import AVFoundation
import Combine

/// Owns the camera capture session for the Camera tab. Battery/privacy
/// rule (see CLAUDE.md "Performance"): the session exists only between
/// `start()` and `stop()`; nothing polls. Adapted in spirit from
/// boring.notch's `WebcamManager` (auth states, device availability),
/// minus its singleton shape.
///
/// `AVCaptureSession.startRunning()` blocks, so the session is only
/// touched on `sessionQueue`; `phase` is only touched on the main actor.
@MainActor
final class CameraMirrorSource: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, live, denied, noCamera
    }

    @Published private(set) var phase: Phase = .idle

    var isLive: Bool { phase == .live || phase == .starting }

    /// `AVCaptureSession` isn't `Sendable`; it's confined to `sessionQueue`
    /// by convention, hence the unchecked box.
    private final class SessionBox: @unchecked Sendable {
        let session = AVCaptureSession()
    }

    private let box = SessionBox()
    private let sessionQueue = DispatchQueue(label: "atelier.camera.session")
    /// Bumped on every start/stop so a slow `startRunning` that finishes
    /// after a `stop()` can tell it's stale and shut itself down.
    private var generation = 0

    /// One layer for the life of the source; the view just hosts it.
    let previewLayer: AVCaptureVideoPreviewLayer

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: box.session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    func toggle() {
        switch phase {
        case .idle, .noCamera: start()
        case .starting, .live: stop()
        case .denied: CameraPermission.openSystemSettings()
        }
    }

    func start() {
        guard phase == .idle || phase == .noCamera || phase == .denied else { return }
        generation += 1
        let myGeneration = generation
        phase = .starting

        Task { @MainActor in
            switch CameraPermission.status {
            case .authorized:
                break
            case .notDetermined:
                guard await CameraPermission.requestAccess() else {
                    if myGeneration == generation { phase = .denied }
                    return
                }
            default:
                if myGeneration == generation { phase = .denied }
                return
            }
            // The user may have tapped off / retracted during the prompt.
            guard myGeneration == generation else { return }

            let box = self.box
            let queue = sessionQueue
            let started: Bool = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: Self.configureAndRun(box.session))
                }
            }
            guard myGeneration == generation else {
                // Stale: a stop() came in while we were starting.
                queue.async { box.session.stopRunning() }
                return
            }
            phase = started ? .live : .noCamera
        }
    }

    func stop() {
        generation += 1
        if phase != .denied { phase = .idle }
        let box = self.box
        sessionQueue.async {
            box.session.stopRunning()
        }
    }

    /// Runs on `sessionQueue`. Returns false if there's no usable camera.
    private nonisolated static func configureAndRun(_ session: AVCaptureSession) -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .medium
        for input in session.inputs { session.removeInput(input) }
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        session.startRunning()
        return session.isRunning
    }
}
