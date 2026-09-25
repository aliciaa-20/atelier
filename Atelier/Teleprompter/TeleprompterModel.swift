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

    init(store: ScriptStore = .shared, persistsWPM: Bool = true) {
        self.store = store
        self.persistsWPM = persistsWPM
        scroll = TeleprompterScroll(totalWords: 0, wpm: AtelierSettings.teleprompterWPM)
        scriptObserver = NotificationCenter.default.addObserver(
            forName: ScriptStore.didChange, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadScript() }
        }
        reloadScript()
    }

    // MARK: Script and layout

    /// Re-reads the script and starts over, paused, at the top: a script
    /// edited mid-play must never leave the position past the new end.
    func reloadScript() {
        cancelFinishTask()
        script = TeleprompterScript(text: store.load())
        scroll = TeleprompterScroll(totalWords: script.wordCount, wpm: scroll.wpm)
        isPlaying = false
        pausedForPointer = false
        relayout()
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
        if isPlaying { pause(now: now) } else { play(now: now) }
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
