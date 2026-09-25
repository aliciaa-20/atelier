import Foundation

/// Where each *display* line starts (a word index), for whatever width and
/// font the view is using. Turns a word position into a fractional line
/// position (integer part = line, fraction = progress through it), which
/// is what drives the smooth vertical glide and the Focus Guide. The
/// wrapping itself (needs fonts) lives in `TeleprompterLineWrapper`; this
/// type stays pure (Invariant 1).
struct TeleprompterLines: Equatable {
    /// Ascending; `starts[0] == 0` when there is any text.
    let starts: [Int]
    let totalWords: Int

    static let empty = TeleprompterLines(starts: [], totalWords: 0)

    var count: Int { starts.count }

    func linePosition(forWord word: Double) -> Double {
        guard !starts.isEmpty else { return 0 }
        let clamped = min(max(word, 0), Double(totalWords))
        // Largest index whose start is <= clamped.
        var lo = 0
        var hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Double(starts[mid]) <= clamped { lo = mid } else { hi = mid - 1 }
        }
        let lineStart = Double(starts[lo])
        let lineEnd = lo + 1 < starts.count ? Double(starts[lo + 1]) : Double(totalWords)
        let span = lineEnd - lineStart
        let fraction = span > 0 ? (clamped - lineStart) / span : 0
        return Double(lo) + min(fraction, 1)
    }

    /// Inverse of `linePosition(forWord:)`: the (fractional) word index at a
    /// (fractional) line position, clamped to the script. Lets a hand scroll
    /// measured in lines move the word position.
    func wordPosition(forLine line: Double) -> Double {
        guard !starts.isEmpty else { return 0 }
        let clamped = min(max(line, 0), Double(starts.count))
        let index = min(Int(clamped), starts.count - 1)
        let lineStart = Double(starts[index])
        let lineEnd = index + 1 < starts.count ? Double(starts[index + 1]) : Double(totalWords)
        return lineStart + (lineEnd - lineStart) * min(clamped - Double(index), 1)
    }

    func currentLine(forWord word: Double) -> Int {
        guard !starts.isEmpty else { return 0 }
        return min(Int(linePosition(forWord: word)), starts.count - 1)
    }

    /// The lines worth building views for, so a 5,000-word script renders
    /// a handful of `Text`s, not thousands.
    func visibleLines(around linePosition: Double, behind: Int, ahead: Int) -> Range<Int> {
        guard !starts.isEmpty else { return 0..<0 }
        let current = min(max(Int(linePosition), 0), starts.count - 1)
        return max(0, current - behind) ..< min(starts.count, current + ahead + 1)
    }
}
