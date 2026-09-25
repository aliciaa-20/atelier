import AppKit
import SwiftUI

/// The one font the teleprompter uses, in both worlds. The wrapper
/// measures with the `NSFont`; the view draws with the matching SwiftUI
/// font, and each display line is its own single-line `Text`, so SwiftUI
/// never re-wraps what the wrapper already wrapped.
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

/// Greedy word wrap into display lines for a width and font, reporting
/// where each line starts as a word index. Each source paragraph wraps on
/// its own, so a paragraph always begins a new line. Breaks only *between*
/// words: CoreText's framesetter also breaks inside hyphenated words and
/// URLs, which left lines wider than the panel with their tails clipped
/// (found in the final review). A word wider than `width` gets a line to
/// itself and is clipped by the view. Needs AppKit fonts, so it lives
/// outside the pure `Notch/` layer.
enum TeleprompterLineWrapper {
    static func lines(for script: TeleprompterScript, font: NSFont, width: CGFloat) -> TeleprompterLines {
        guard width > 0, !script.isEmpty else {
            return TeleprompterLines(starts: [], totalWords: script.wordCount)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func measure(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: attributes).size().width
        }

        var starts: [Int] = []
        for paragraph in script.paragraphs {
            var lineText = ""
            for index in paragraph {
                let word = script.words[index]
                if lineText.isEmpty {
                    starts.append(index)
                    lineText = word
                    continue
                }
                // Measure the real candidate line (not summed word widths) so
                // kerning is included and no line is wider than `width`.
                let candidate = lineText + " " + word
                if measure(candidate) <= width {
                    lineText = candidate
                } else {
                    starts.append(index)
                    lineText = word
                }
            }
        }
        return TeleprompterLines(starts: starts, totalWords: script.wordCount)
    }
}
