import Testing
import AppKit
@testable import Atelier

struct TeleprompterLineWrapperTests {
    private let font = TeleprompterFont.nsFont(size: 15, mono: false)
    private let sentence = "The quick brown fox jumps over the lazy dog and keeps on running far away"

    @Test func narrowerWidthMakesMoreLines() {
        let script = TeleprompterScript(text: sentence)
        let wide = TeleprompterLineWrapper.lines(for: script, font: font, width: 600)
        let narrow = TeleprompterLineWrapper.lines(for: script, font: font, width: 120)
        #expect(wide.count == 1)
        #expect(narrow.count > wide.count)
        #expect(narrow.totalWords == script.wordCount)
    }

    @Test func startsAreStrictlyAscendingAndBeginAtZero() {
        let script = TeleprompterScript(text: sentence)
        let lines = TeleprompterLineWrapper.lines(for: script, font: font, width: 120)
        #expect(lines.starts.first == 0)
        #expect(zip(lines.starts, lines.starts.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func everyParagraphStartsANewLine() {
        let script = TeleprompterScript(text: "short one\nshort two\nshort three")
        let lines = TeleprompterLineWrapper.lines(for: script, font: font, width: 600)
        #expect(lines.starts == [0, 2, 4])
    }

    // Review Focus 2: an unbreakable word wider than the panel is one line.
    @Test func aWordWiderThanTheWidthIsASingleLineWithNoDuplicates() {
        let script = TeleprompterScript(text: "Supercalifragilisticexpialidocious")
        let lines = TeleprompterLineWrapper.lines(for: script, font: font, width: 20)
        #expect(lines.starts == [0])
    }

    @Test func emptyScriptAndZeroWidthAreSafe() {
        #expect(TeleprompterLineWrapper.lines(for: TeleprompterScript(text: ""), font: font, width: 300).count == 0)
        #expect(TeleprompterLineWrapper.lines(for: TeleprompterScript(text: sentence), font: font, width: 0).count == 0)
    }
}
