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
    static let shared = TeleprompterModel()

    @Published private(set) var script = TeleprompterScript(text: "")
    @Published private(set) var lines = TeleprompterLines.empty
    @Published private(set) var scroll: TeleprompterScroll
    @Published private(set) var isPlaying = false
    /// True while playback is paused only because the pointer is over the
    /// notch; it resumes on exit.
    @Published private(set) var pausedForPointer = false

    /// Playing, or about to resume when the pointer leaves. The hold-open
    /// rule and the "retract when done" logic use this, not `isPlaying`,
    /// so the hover-out that triggers the resume doesn't retract the notch.
    var wantsNotchOpen: Bool { isPlaying || pausedForPointer }

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

    /// `initialWPM` defaults to the saved speed; tests pass a fixed one so
    /// they don't depend on whatever the user last chose.
    init(store: ScriptStore = .shared, persistsWPM: Bool = true, initialWPM: Double = AtelierSettings.teleprompterWPM) {
        self.store = store
        self.persistsWPM = persistsWPM
        scroll = TeleprompterScroll(totalWords: 0, wpm: initialWPM)
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
        if wasPlaying, !scroll.isFinished(at: now) { scroll.play(at: now) }
        isPlaying = scroll.isPlaying(at: now)
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
        scroll.play(at: now)
        isPlaying = scroll.isPlaying(at: now)
        pausedForPointer = false
        scheduleFinish(now: now)
    }

    func pause(now: Date = .now) {
        scroll.pause(at: now)
        isPlaying = false
        pausedForPointer = false
        cancelFinishTask()
    }

    func toggle(now: Date = .now) {
        // Held by the pointer counts as playing: pausing must stop it for
        // good, not resume under the pointer.
        if wantsNotchOpen { pause(now: now) } else { play(now: now) }
    }

    func restart(now: Date = .now) {
        scroll.seek(to: 0, at: now)
        scheduleFinish(now: now)
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
        isPlaying = scroll.isPlaying(at: now)
        scheduleFinish(now: now)   // reschedules only if somehow still playing
    }

    /// Pause while the pointer is over the notch, resume when it leaves,
    /// but only if it was playing when the pointer arrived. Pressing Play
    /// with the pointer already inside plays normally.
    func setPointerInside(_ inside: Bool, now: Date = .now) {
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

    // MARK: Finish timer

    private func scheduleFinish(now: Date) {
        cancelFinishTask()
        guard scroll.isPlaying(at: now) else { return }
        // A hair past the end so `settle` sees it as finished.
        let wait = scroll.secondsRemaining(at: now) + 0.05
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
