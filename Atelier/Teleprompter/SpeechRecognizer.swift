import AVFoundation
import Foundation
import Speech

/// Streaming on-device speech recognition for voice sync. Alive only while the
/// teleprompter is listening (`start`/`stop`), so the microphone indicator and
/// CPU cost track exactly what the user sees. Manual-verification only, like
/// the other `System/*` pieces: it needs a real mic and a TCC grant.
///
/// Threading: the audio tap and the recognition callback run on background
/// queues. Under Swift 6's default MainActor isolation a closure written
/// inside this class would be MainActor-isolated and trap on those queues, so
/// both callbacks are built in `nonisolated` helpers and hop to the main
/// actor explicitly.
@MainActor
final class SpeechRecognizer: ObservableObject, SpeechWordSource {
    static let shared = SpeechRecognizer()

    var onWords: (([String]) -> Void)?
    var onFailure: ((String) -> Void)?
    /// Microphone loudness 0...1 for the "Listening" pill, ~15 fps, while running.
    @Published private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    /// Bumped on every (re)start/stop so a cancelled task's late callback is ignored.
    private var generation = 0
    private var quickFailures = 0
    private var configObserver: NSObjectProtocol?

    // MARK: SpeechWordSource

    func prepare() async -> String? {
        if MicrophonePermission.status == .notDetermined { _ = await MicrophonePermission.requestAccess() }
        guard MicrophonePermission.status == .authorized else {
            return "Microphone access is off. Turn it on in System Settings > Privacy & Security."
        }
        if SpeechPermission.status == .notDetermined { _ = await SpeechPermission.requestAccess() }
        guard SpeechPermission.status == .authorized else {
            return "Speech Recognition is off. Turn it on in System Settings > Privacy & Security."
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            return "Speech recognition isn't available for your language right now."
        }
        // On-device only: never send the user's voice to a server.
        guard recognizer.supportsOnDeviceRecognition else {
            return "Your language has no on-device speech model, so voice sync stays off to keep your voice private."
        }
        self.recognizer = recognizer
        return nil
    }

    func start() {
        guard !running, let recognizer else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            fail("No microphone was found.")
            return
        }
        running = true
        quickFailures = 0
        beginTask(recognizer)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box: box) { [weak self] level in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.level = level } }
        })
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The audio route changed (AirPods connected, device unplugged):
            // the engine has stopped. Say so instead of leaving a dead mic.
            MainActor.assumeIsolated { self?.fail("The audio device changed, so voice sync stopped.") }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            fail("The microphone couldn't start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        task?.cancel()
        task = nil
        box.set(nil)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        level = 0
    }

    // MARK: Recognition task

    private func beginTask(_ recognizer: SFSpeechRecognizer) {
        generation += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        box.set(request)
        let current = generation
        task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] words, isFinal, failed in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(words: words, isFinal: isFinal, failed: failed, generation: current) }
            }
        }
    }

    private func handle(words: [String]?, isFinal: Bool, failed: Bool, generation gen: Int) {
        guard running, gen == generation else { return }
        if let words, !words.isEmpty {
            quickFailures = 0
            onWords?(words)
        }
        guard isFinal || failed else { return }
        // Recognition tasks end after about a minute, or on a hiccup. Start a
        // fresh request; the matcher's cursor lives in the model, so nothing
        // is lost. Repeated failures with no words in between = give up.
        if failed, words?.isEmpty ?? true { quickFailures += 1 }
        if quickFailures >= 3 {
            fail("Speech recognition stopped working.")
            return
        }
        task?.cancel()
        if let recognizer { beginTask(recognizer) }
    }

    private func fail(_ reason: String) {
        stop()
        onFailure?(reason)
    }

    // MARK: Background-queue helpers (nonisolated on purpose)

    nonisolated private static func makeTap(box: RequestBox, onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        var buffers = 0
        return { buffer, _ in
            box.append(buffer)
            buffers += 1
            // ~1024 frames per buffer: every 3rd buffer is roughly 15 per second.
            guard buffers % 3 == 0, let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(count)).squareRoot()
            onLevel(min(1, rms * 8))
        }
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        deliver: @escaping @Sendable ([String]?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            deliver(result?.bestTranscription.segments.map(\.substring), result?.isFinal ?? false, error != nil)
        }
    }
}

/// Hands the current recognition request to the audio thread safely; the tap
/// is installed once per start while requests are swapped on restarts.
private nonisolated final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = new
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}
