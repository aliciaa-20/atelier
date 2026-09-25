import AppKit
import CoreText
import SwiftUI

/// The one font the teleprompter uses, in both worlds. The wrapper
/// measures with the `NSFont`; the view draws with the matching SwiftUI
/// font, and each display line is its own single-line `Text`, so SwiftUI
/// never re-wraps what CoreText already wrapped.
enum TeleprompterFont {
    static func nsFont(size: Double, mono: Bool) -> NSFont {
        mono
            ? .monospacedSystemFont(ofSize: size, weight: .bold)
            : .systemFont(ofSize: size, weight: .bold)
    }

    static func swiftUIFont(size: Double, mono: Bool) -> Font {
        .system(size: size, weight: .bold, design: mono ? .monospaced : .default)
    }
}

/// Word-wraps a script into display lines for a width and font using
/// CoreText, and reports where each line starts as a word index. Each
/// source paragraph wraps on its own, so a paragraph always begins a new
/// line. Needs AppKit fonts, so it lives outside the pure `Notch/` layer.
enum TeleprompterLineWrapper {
    static func lines(for script: TeleprompterScript, font: NSFont, width: CGFloat) -> TeleprompterLines {
        guard width > 0, !script.isEmpty else {
            return TeleprompterLines(starts: [], totalWords: script.wordCount)
        }
        var starts: [Int] = []

        for paragraph in script.paragraphs {
            var text = ""
            var wordOffsets: [Int] = []           // UTF-16 offset of each word in `text`
            for (index, word) in script.words[paragraph].enumerated() {
                if index > 0 { text += " " }
                wordOffsets.append(text.utf16.count)
                text += word
            }

            let framesetter = CTFramesetterCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font])
            )
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1_000_000), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            let ctLines = (CTFrameGetLines(frame) as? [CTLine]) ?? []

            for line in ctLines {
                let location = CTLineGetStringRange(line).location
                // Largest word whose offset is <= the line's first character.
                var lo = 0
                var hi = wordOffsets.count - 1
                while lo < hi {
                    let mid = (lo + hi + 1) / 2
                    if wordOffsets[mid] <= location { lo = mid } else { hi = mid - 1 }
                }
                let wordIndex = paragraph.lowerBound + lo
                // A single word wider than `width` is character-wrapped by
                // CoreText into several lines that all map to the same word;
                // keep one line for it (the view lets it overflow and clips).
                if starts.last != wordIndex { starts.append(wordIndex) }
            }
        }
        return TeleprompterLines(starts: starts, totalWords: script.wordCount)
    }
}
