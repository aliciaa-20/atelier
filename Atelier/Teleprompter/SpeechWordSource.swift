import Foundation

/// Where spoken words come from. `SpeechRecognizer` is the real one; tests use
/// a fake, so the model's voice-mode rules are unit-tested without a microphone.
@MainActor
protocol SpeechWordSource: AnyObject {
    /// The full transcript so far, as words (it grows and is revised).
    var onWords: (([String]) -> Void)? { get set }
    /// The source can't continue (device lost, recognizer died). Argument: why.
    var onFailure: ((String) -> Void)? { get set }
    /// Asks for permissions and checks the recognizer is usable. Returns nil
    /// when ready, otherwise a short user-facing reason.
    func prepare() async -> String?
    /// Starts capturing. Only ever called while listening.
    func start()
    /// Stops capturing and releases the microphone.
    func stop()
}
