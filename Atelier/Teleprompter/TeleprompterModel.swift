import AppKit
import Combine
import Foundation

/// State for the Teleprompter tab: the script, its wrapped lines, and the
/// time-anchored scroll. Nothing here ticks: the view asks
/// `scroll.position(at:)` on its own (capped) schedule, and the only timer
/// is one sleeping task that fires when a playing script reaches its end,
/// so a paused or finished teleprompter costs nothing.
@MainActor
final class TeleprompterModel: ObservableObject {
    static let shared = TeleprompterModel(speech: SpeechRecognizer.shared)

    @Published private(set) var script = TeleprompterScript(text: "")
    @Published private(set) var lines = TeleprompterLines.empty
    @Published private(set) var scroll: TeleprompterScroll
    @Published private(set) var isPlaying = false
    /// True while playback is paused only because the pointer is over the
    /// notch; it resumes on exit.
    @Published private(set) var pausedForPointer = false

    /// Voice sync is on: the script follows the speaker's voice, and
    /// "playing" means *listening*, not "the clock is running".
    @Published private(set) var voiceSyncEnabled = false
    /// Why voice sync couldn't be used (permission denied, no on-device
    /// model, device lost); nil when there is nothing to report. The model
    /// then runs on the manual WPM pace.
    @Published private(set) var voiceUnavailableReason: String?
    /// Voice mode only: the script is currently gliding toward the spoken
    /// position. Views tick only while this is true.
    @Published private(set) var isGliding = false

    /// Whether views need to redraw continuously: the clock is running
    /// (manual) or a glide is in flight (voice).
    var isAnimating: Bool { voiceSyncEnabled ? isGliding : isPlaying }

    /// Playing, or about to resume when the pointer leaves. The hold-open
    /// rule and the "retract when done" logic use this, not `isPlaying`,
    /// so the hover-out that triggers the resume doesn't retract the notch.
    var wantsNotchOpen: Bool { isPlaying || pausedForPointer }

    /// True once the script has run to its end (as opposed to being paused
    /// by hand). The root view retracts the notch after a finish, not after a
    /// manual pause, so a presenter who pauses keeps their place in view.
    func hasFinished(now: Date = .now) -> Bool {
        scroll.isFinished(at: now)
    }

    /// False for an empty script: nothing to play, so nothing should open
    /// the notch for it (the global hotkey checks this).
    var canPlay: Bool { !script.isEmpty }

    private struct LayoutKey: Equatable {
        var width: CGFloat
        var fontSize: Double
        var mono: Bool
    }

    private let store: ScriptStore
    /// `persistsWPM` is false in tests: they run inside the real app
    /// process, and must not overwrite the user's saved speed.
    private let persistsWPM: Bool
    private var layout: LayoutKey?
    private var finishTask: Task<Void, Never>?
    private var scriptObserver: NSObjectProtocol?
    private let speech: SpeechWordSource?
    private let persistsVoiceSync: Bool
    private var matcher = ScriptMatcher(scriptWords: [])
    private var glideTask: Task<Void, Never>?
    private var isPreparingVoice = false

    /// `initialWPM` defaults to the saved speed; tests pass a fixed one so
    /// they don't depend on whatever the user last chose.
    init(
        store: ScriptStore = .shared,
        speech: SpeechWordSource? = nil,
        persistsWPM: Bool = true,
        persistsVoiceSync: Bool = true,
        initialWPM: Double = AtelierSettings.teleprompterWPM
    ) {
        self.store = store
        self.speech = speech
        self.persistsWPM = persistsWPM
        self.persistsVoiceSync = persistsVoiceSync
        scroll = TeleprompterScroll(totalWords: 0, wpm: initialWPM)
        speech?.onWords = { [weak self] words in self?.applySpeech(words: words) }
        speech?.onFailure = { [weak self] reason in self?.failVoiceSync(reason) }
        scriptObserver = NotificationCenter.default.addObserver(
            forName: ScriptStore.didChange, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadScript() }
        }
        reloadScript()
    }

    // MARK: Script and layout

    /// Re-reads the script. Editing keeps your place and keeps playing (a
    /// shorter script clamps the position to its end, and a script that is
    /// then already finished stops), so fixing a typo mid-read doesn't
    /// throw you back to the top.
    func reloadScript(now: Date = .now) {
        let reloaded = TeleprompterScript(text: store.load())
        // Saving the same words again (e.g. opening the Settings pane) must
        // not disturb anything.
        guard reloaded != script else { return }
        let wasPlaying = isPlaying
        let oldPosition = scroll.position(at: now)
        cancelFinishTask()
        script = reloaded
        scroll = TeleprompterScroll(totalWords: reloaded.wordCount, wpm: scroll.wpm)
        scroll.seek(to: oldPosition, at: now)
        // `play` on a finished script would restart it, so only resume when
        // there is still script left to read.
        if voiceSyncEnabled {
            glideTask?.cancel()
            isGliding = false
            scroll.enterVoiceMode(at: now)
            matcher = ScriptMatcher(scriptWords: reloaded.words, cursor: Int(scroll.position(at: now)))
            isPlaying = wasPlaying && !scroll.isFinished(at: now)
            if !isPlaying { speech?.stop() }
        } else {
            if wasPlaying, !scroll.isFinished(at: now) { scroll.play(at: now) }
            isPlaying = scroll.isPlaying(at: now)
        }
        relayout()
        scheduleFinish(now: now)
    }

    func updateLayout(width: CGFloat, fontSize: Double, mono: Bool) {
        let key = LayoutKey(width: width, fontSize: fontSize, mono: mono)
        guard key != layout else { return }
        layout = key
        relayout()
    }

    private func relayout() {
        guard let layout else {
            lines = TeleprompterLines(starts: [], totalWords: script.wordCount)
            return
        }
        let font = TeleprompterFont.nsFont(size: layout.fontSize, mono: layout.mono)
        lines = TeleprompterLineWrapper.lines(for: script, font: font, width: layout.width)
    }

    func lineText(_ index: Int) -> String {
        guard lines.starts.indices.contains(index) else { return "" }
        let start = lines.starts[index]
        let end = index + 1 < lines.starts.count ? lines.starts[index + 1] : script.wordCount
        return script.words[start..<end].joined(separator: " ")
    }

    // MARK: Transport

    func play(now: Date = .now) {
        if voiceSyncEnabled { startListening(now: now); return }
        scroll.play(at: now)
        isPlaying = scroll.isPlaying(at: now)
        pausedForPointer = false
        scheduleFinish(now: now)
    }

    func pause(now: Date = .now) {
        if voiceSyncEnabled { speech?.stop() }
        scroll.pause(at: now)
        isPlaying = false
        isGliding = false
        pausedForPointer = false
        glideTask?.cancel()
        cancelFinishTask()
    }

    func toggle(now: Date = .now) {
        // Held by the pointer counts as playing: pausing must stop it for
        // good, not resume under the pointer.
        if wantsNotchOpen { pause(now: now) } else { play(now: now) }
    }

    func setWPM(_ wpm: Double, now: Date = .now) {
        scroll.setWPM(wpm, at: now)
        if persistsWPM { AtelierSettings.teleprompterWPM = scroll.wpm }
        scheduleFinish(now: now)
    }

    func stepWPM(by delta: Double, now: Date = .now) {
        setWPM(scroll.wpm + delta, now: now)
    }

    /// Called when a playing script has run off the end.
    func settle(now: Date = .now) {
        scroll.settle(at: now)
        if voiceSyncEnabled {
            // Voice mode: finished only once the glide has reached the end.
            guard scroll.isFinished(at: now) else { return }
            speech?.stop()
            isPlaying = false
            isGliding = false
            return
        }
        isPlaying = scroll.isPlaying(at: now)
        scheduleFinish(now: now)   // reschedules only if somehow still playing
    }

    /// Pause while the pointer is over the notch, resume when it leaves,
    /// but only if it was playing when the pointer arrived. Pressing Play
    /// with the pointer already inside plays normally.
    func setPointerInside(_ inside: Bool, now: Date = .now) {
        // Voice mode: the pointer leaving must not kill the mic mid-read.
        guard !voiceSyncEnabled else { return }
        if inside {
            guard isPlaying else { return }
            pause(now: now)
            pausedForPointer = true
        } else if pausedForPointer {
            play(now: now)
        }
    }

    /// Hand-scrolls a script that isn't playing by a number of display lines
    /// (positive = further into the script). Ignored while playing; allowed
    /// while held by the pointer, so it resumes from where you scrolled to.
    func scrollLines(by delta: Double, now: Date = .now) {
        guard !isPlaying, !lines.starts.isEmpty else { return }
        let line = lines.linePosition(forWord: scroll.position(at: now)) + delta
        scroll.seek(to: lines.wordPosition(forLine: line), at: now)
    }

    // MARK: Voice sync

    /// Turns voice sync on or off. Turning on asks for permissions (once) and
    /// checks the recognizer; on any problem it stays off with a reason and
    /// the model keeps working on the manual WPM pace.
    func setVoiceSync(_ on: Bool, now: Date = .now) async {
        guard on != voiceSyncEnabled, !isPreparingVoice else { return }
        if on {
            guard let speech else {
                failVoiceSync("Voice sync isn't available on this Mac.", now: now)
                return
            }
            isPreparingVoice = true
            let problem = await speech.prepare()
            isPreparingVoice = false
            if let problem {
                failVoiceSync(problem, now: now)
                return
            }
            pause(now: now)
            voiceUnavailableReason = nil
            voiceSyncEnabled = true
            scroll.enterVoiceMode(at: now)
            matcher = ScriptMatcher(scriptWords: script.words, cursor: Int(scroll.position(at: now)))
        } else {
            pause(now: now)   // stops the mic while still in voice mode
            voiceSyncEnabled = false
            voiceUnavailableReason = nil
            scroll.exitVoiceMode(at: now)
        }
        if persistsVoiceSync { AtelierSettings.teleprompterVoiceSync = on }
    }

    /// Falls back to manual pace, keeping the reason so the UI can say why.
    private func failVoiceSync(_ reason: String, now: Date = .now) {
        if voiceSyncEnabled {
            pause(now: now)
            voiceSyncEnabled = false
            scroll.exitVoiceMode(at: now)
        }
        voiceUnavailableReason = reason
        if persistsVoiceSync { AtelierSettings.teleprompterVoiceSync = false }
    }

    private func startListening(now: Date) {
        guard let speech, !script.isEmpty else { return }
        if scroll.isFinished(at: now) { scroll.seek(to: 0, at: now) }
        scroll.enterVoiceMode(at: now)
        matcher.reset(cursor: Int(scroll.position(at: now)))
        isPlaying = true
        pausedForPointer = false
        speech.start()
    }

    /// Speech recognizer output: words heard so far -> matcher -> scroll target.
    func applySpeech(words: [String], now: Date = .now) {
        guard voiceSyncEnabled, isPlaying, let cursor = matcher.update(spoken: words) else { return }
        applySpeechPosition(cursor, now: now)
    }

    /// The speaker has reached word `cursor` of the script: glide there.
    func applySpeechPosition(_ cursor: Int, now: Date = .now) {
        scroll.setTarget(Double(cursor), at: now)
        isGliding = true
        glideTask?.cancel()
        let wait = scroll.glideSecondsRemaining(at: now) + 0.05
        glideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.isGliding = false
        }
        scheduleFinish(now: now)
    }

    // MARK: Finish timer

    private func scheduleFinish(now: Date) {
        cancelFinishTask()
        // Voice mode: only once the speaker has reached the last word; a
        // silent speaker mid-script must never "finish".
        if voiceSyncEnabled, matcher.cursor < script.wordCount { return }
        guard scroll.isPlaying(at: now) else { return }
        // A hair past the end so `settle` sees it as finished.
        let seconds = voiceSyncEnabled ? scroll.glideSecondsRemaining(at: now) : scroll.secondsRemaining(at: now)
        let wait = seconds + 0.05
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func cancelFinishTask() {
        finishTask?.cancel()
        finishTask = nil
    }
}
