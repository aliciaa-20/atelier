import Foundation

/// A script split into words, plus which words start a new line of the
/// source text. Every non-empty source line is one "paragraph" and always
/// begins a new display line (scripts are usually typed one sentence per
/// line); blank lines are ignored. Pure and Foundation-only (Invariant 1).
struct TeleprompterScript: Equatable {
    let words: [String]
    /// Word-index ranges, one per non-empty source line, in order.
    let paragraphs: [Range<Int>]

    var wordCount: Int { words.count }
    var isEmpty: Bool { words.isEmpty }

    init(text: String) {
        var words: [String] = []
        var paragraphs: [Range<Int>] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lineWords = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !lineWords.isEmpty else { continue }
            paragraphs.append(words.count ..< words.count + lineWords.count)
            words.append(contentsOf: lineWords)
        }
        self.words = words
        self.paragraphs = paragraphs
    }
}
