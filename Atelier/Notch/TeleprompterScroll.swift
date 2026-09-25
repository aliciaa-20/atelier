import Foundation

/// Where the script is, as a fractional word index, derived from a start
/// date instead of a mutating tick: `position(at:)` is a pure function of
/// time, so the view can ask "where are we now?" on every frame without
/// any timer writing state. Pausing, changing speed, or seeking "re-anchors"
/// (bakes the current position in) so nothing ever jumps. Pure and
/// Foundation-only (Invariant 1); the stage-4 speech source drives it via
/// `seek(to:at:)` instead of the clock.
struct TeleprompterScroll: Equatable {
    static let wpmRange: ClosedRange<Double> = 50...300
    static let defaultWPM: Double = 140

    private(set) var totalWords: Int
    private(set) var wpm: Double
    private var anchorPosition: Double = 0
    /// Non-nil while playing: the moment `anchorPosition` was true.
    private var anchorDate: Date?

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
        return min(Double(totalWords), anchorPosition + elapsed * wpm / 60)
    }

    func progress(at date: Date) -> Double {
        guard totalWords > 0 else { return 0 }
        return position(at: date) / Double(totalWords)
    }

    func isFinished(at date: Date) -> Bool {
        totalWords > 0 && position(at: date) >= Double(totalWords)
    }

    /// Playing means running and not yet at the end.
    func isPlaying(at date: Date) -> Bool {
        anchorDate != nil && !isFinished(at: date)
    }

    var secondsTotal: TimeInterval { Double(totalWords) / wpm * 60 }

    func secondsElapsed(at date: Date) -> TimeInterval {
        position(at: date) / wpm * 60
    }

    func secondsRemaining(at date: Date) -> TimeInterval {
        max(0, Double(totalWords) - position(at: date)) / wpm * 60
    }

    mutating func play(at date: Date) {
        guard totalWords > 0 else { return }
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
    }

    mutating func setWPM(_ newWPM: Double, at date: Date) {
        if anchorDate != nil {
            anchorPosition = position(at: date)
            anchorDate = date
        }
        wpm = Self.clamped(newWPM)
    }

    mutating func seek(to word: Double, at date: Date) {
        anchorPosition = min(max(word, 0), Double(totalWords))
        if anchorDate != nil { anchorDate = date }
    }

    /// Freezes a script that has run off the end so it stops being "playing".
    mutating func settle(at date: Date) {
        guard isFinished(at: date) else { return }
        anchorPosition = Double(totalWords)
        anchorDate = nil
    }
}
