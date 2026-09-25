import Foundation

/// Where the script is, as a fractional word index, derived from a start
/// date instead of a mutating tick: `position(at:)` is a pure function of
/// time, so the view can ask "where are we now?" on every frame without
/// any timer writing state. Pausing, changing speed, or seeking "re-anchors"
/// (bakes the current position in) so nothing ever jumps. Pure and
/// Foundation-only (Invariant 1); the stage-4 speech source drives it through
/// voice mode (`setTarget`) instead of the clock.
struct TeleprompterScroll: Equatable {
    static let wpmRange: ClosedRange<Double> = 50...300
    static let defaultWPM: Double = 140

    private(set) var totalWords: Int
    private(set) var wpm: Double
    private var anchorPosition: Double = 0
    /// Non-nil while playing: the moment `anchorPosition` was true.
    private var anchorDate: Date?

    /// Non-nil in voice mode: the word index the speech recognizer says the
    /// speaker has reached. `position(at:)` then glides from the anchor toward
    /// it instead of following the clock, and stops on arrival (so a silent
    /// speaker = a still script, with nothing ticking).
    private var target: Double?

    /// However big the gap, the glide arrives within this many seconds, so a
    /// fast reader doesn't watch the script lag behind.
    static let voiceCatchUpSeconds: Double = 1.5

    var isVoiceMode: Bool { target != nil }

    init(totalWords: Int, wpm: Double = TeleprompterScroll.defaultWPM) {
        self.totalWords = max(0, totalWords)
        self.wpm = Self.clamped(wpm)
    }

    private static func clamped(_ wpm: Double) -> Double {
        min(max(wpm, wpmRange.lowerBound), wpmRange.upperBound)
    }

    func position(at date: Date) -> Double {
        guard let anchorDate else { return anchorPosition }
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        if let target {
            return min(target, anchorPosition + elapsed * glideRate(gap: target - anchorPosition))
        }
        return min(Double(totalWords), anchorPosition + elapsed * wpm / 60)
    }

    /// Words per second while gliding: at least the reading speed, faster when
    /// the gap is large enough that it wouldn't arrive within the catch-up time.
    private func glideRate(gap: Double) -> Double {
        max(wpm / 60, max(0, gap) / Self.voiceCatchUpSeconds)
    }

    func isGliding(at date: Date) -> Bool {
        guard let target else { return false }
        return position(at: date) < target
    }

    func glideSecondsRemaining(at date: Date) -> TimeInterval {
        guard let target, anchorDate != nil else { return 0 }
        let rate = glideRate(gap: target - anchorPosition)
        return max(0, target - position(at: date)) / rate
    }

    func progress(at date: Date) -> Double {
        guard totalWords > 0 else { return 0 }
        return position(at: date) / Double(totalWords)
    }

    func isFinished(at date: Date) -> Bool {
        totalWords > 0 && position(at: date) >= Double(totalWords)
    }

    /// Playing means running and not yet at the end. In voice mode it means
    /// gliding toward the spoken position.
    func isPlaying(at date: Date) -> Bool {
        if target != nil { return isGliding(at: date) }
        return anchorDate != nil && !isFinished(at: date)
    }

    var secondsTotal: TimeInterval { Double(totalWords) / wpm * 60 }

    func secondsElapsed(at date: Date) -> TimeInterval {
        position(at: date) / wpm * 60
    }

    func secondsRemaining(at date: Date) -> TimeInterval {
        max(0, Double(totalWords) - position(at: date)) / wpm * 60
    }

    mutating func play(at date: Date) {
        guard totalWords > 0, target == nil else { return }
        if isFinished(at: date) {
            anchorPosition = 0
        } else if anchorDate != nil {
            return
        }
        anchorDate = date
    }

    mutating func pause(at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = nil
        if target != nil { target = anchorPosition }
    }

    mutating func setWPM(_ newWPM: Double, at date: Date) {
        if anchorDate != nil {
            anchorPosition = position(at: date)
            anchorDate = date
        }
        wpm = Self.clamped(newWPM)
    }

    /// A hand-scroll or explicit jump. Leaves voice mode (the model re-enters
    /// it when listening resumes), so a leftover glide can't undo the jump.
    mutating func seek(to word: Double, at date: Date) {
        let wasVoice = target != nil
        target = nil
        anchorPosition = min(max(word, 0), Double(totalWords))
        if wasVoice {
            anchorDate = nil
        } else if anchorDate != nil {
            anchorDate = date
        }
    }

    /// Switches to voice mode where the script currently is: nothing moves
    /// until the first `setTarget`.
    mutating func enterVoiceMode(at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = nil
        target = anchorPosition
    }

    mutating func exitVoiceMode(at date: Date) {
        anchorPosition = position(at: date)
        anchorDate = nil
        target = nil
    }

    /// The speaker has reached `word`: glide there. Ignored outside voice
    /// mode; never moves backwards; clamped to the end of the script.
    mutating func setTarget(_ word: Double, at date: Date) {
        guard target != nil else { return }
        anchorPosition = position(at: date)
        target = min(max(word, anchorPosition), Double(totalWords))
        anchorDate = date
    }

    /// Freezes a script that has run off the end so it stops being "playing".
    mutating func settle(at date: Date) {
        guard isFinished(at: date) else { return }
        anchorPosition = Double(totalWords)
        anchorDate = nil
    }
}
