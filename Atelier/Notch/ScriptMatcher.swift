import Foundation

/// Aligns the words the speech recognizer heard to the script, forward-only.
/// Pure and Foundation-only (Invariant 1 style) so it is unit-tested without
/// a microphone.
///
/// Why forward-only and windowed: one misheard word, or a phrase that also
/// appears far away in the script, must never teleport the reader. So only a
/// window of words after the cursor is searched, and the cursor never moves
/// back. The recognizer streams a growing transcript that it revises
/// retroactively, so only the last few spoken words (the "tail") are matched.
struct ScriptMatcher: Equatable {
    /// How many words ahead of the cursor are searched.
    static let windowSize = 30
    /// How many of the most recent spoken words are matched.
    static let tailLength = 4

    /// Matched-word weight needed to advance (long words weigh 1, short 0.5).
    /// The further ahead the match lands, the more evidence it needs, so a
    /// single recurring word can't drag the cursor across the script: a match
    /// up to 3 words ahead needs 1, up to 8 words 1.5, further 2.
    static func requiredScore(distance: Int) -> Double {
        distance <= 3 ? 1.0 : (distance <= 8 ? 1.5 : 2.0)
    }

    private let script: [String]
    /// Number of script words confirmed spoken (= index of the next unread word).
    private(set) var cursor: Int
    /// The last transcript seen (word count + last word). The recognizer
    /// re-sends the same partial transcript, or only revises earlier words;
    /// re-scoring that would hunt for a *later* copy of the last word and
    /// run ahead of the speaker, so only a transcript with something new at
    /// its end is scored.
    private var lastCount = 0
    private var lastWord = ""

    init(scriptWords: [String], cursor: Int = 0) {
        script = scriptWords.map(Self.normalize)
        self.cursor = min(max(cursor, 0), scriptWords.count)
    }

    mutating func reset(cursor: Int) {
        self.cursor = min(max(cursor, 0), script.count)
        lastCount = 0
        lastWord = ""
    }

    /// Feeds the full spoken transcript so far. Returns the new cursor if it
    /// advanced, nil if the words didn't match with enough confidence.
    @discardableResult
    mutating func update(spoken: [String]) -> Int? {
        let heard = spoken.map(Self.normalize).filter { !$0.isEmpty }
        guard let last = heard.last, cursor < script.count else { return nil }
        // Nothing new at the end of the transcript: same words again, or an
        // earlier word revised.
        guard heard.count != lastCount || last != lastWord else { return nil }
        lastCount = heard.count
        lastWord = last
        let tail = Array(heard.suffix(Self.tailLength))

        let lastEnd = min(cursor + Self.windowSize, script.count)
        var best: (end: Int, score: Double)?
        for end in (cursor + 1)...lastEnd {
            // The word just spoken must be the word the cursor lands on.
            guard Self.wordsMatch(last, script[end - 1]) else { continue }
            var score = 0.0
            for (offset, word) in tail.reversed().enumerated() {
                let scriptIndex = end - 1 - offset
                guard scriptIndex >= 0 else { break }
                if Self.wordsMatch(word, script[scriptIndex]) { score += Self.weight(word) }
            }
            // Strictly greater: on a tie the nearest candidate wins.
            if score >= Self.requiredScore(distance: end - cursor), score > (best?.score ?? 0) {
                best = (end, score)
            }
        }
        guard let best else { return nil }
        cursor = best.end
        return cursor
    }

    // MARK: Word comparison

    /// Lowercased, accents folded, letters and digits only.
    static func normalize(_ word: String) -> String {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Equal, or (for longer words) within a small edit distance, so
    /// "recognise"/"recognize" match but "the"/"then" do not.
    static func wordsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 5 else { return false }
        return editDistance(a, b) <= (shorter >= 9 ? 2 : 1)
    }

    private static func weight(_ word: String) -> Double {
        word.count >= 4 ? 1.0 : 0.5
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}
