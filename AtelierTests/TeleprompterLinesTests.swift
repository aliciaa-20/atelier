import Testing
@testable import Atelier

struct TeleprompterLinesTests {
    // Three lines starting at words 0, 4 and 9 of a 12-word script.
    private let lines = TeleprompterLines(starts: [0, 4, 9], totalWords: 12)

    @Test func emptyLinesAreSafe() {
        #expect(TeleprompterLines.empty.linePosition(forWord: 5) == 0)
        #expect(TeleprompterLines.empty.currentLine(forWord: 5) == 0)
        #expect(TeleprompterLines.empty.visibleLines(around: 0, behind: 2, ahead: 3) == 0..<0)
    }

    @Test func linePositionInterpolatesWithinALine() {
        #expect(lines.linePosition(forWord: 0) == 0)
        #expect(lines.linePosition(forWord: 2) == 0.5)
        #expect(lines.linePosition(forWord: 4) == 1)
        #expect(lines.linePosition(forWord: 6.5) == 1.5)
    }

    @Test func linePositionAtTheEndIsPastTheLastLine() {
        #expect(lines.linePosition(forWord: 12) == 3)
        #expect(lines.linePosition(forWord: 999) == 3)
        #expect(lines.linePosition(forWord: -3) == 0)
    }

    @Test func currentLineIsClampedToARealLine() {
        #expect(lines.currentLine(forWord: 0) == 0)
        #expect(lines.currentLine(forWord: 5) == 1)
        #expect(lines.currentLine(forWord: 12) == 2)
    }

    @Test func visibleWindowIsClampedToTheLineCount() {
        #expect(lines.visibleLines(around: 1.5, behind: 2, ahead: 3) == 0..<3)
        let many = TeleprompterLines(starts: Array(0..<10).map { $0 * 3 }, totalWords: 30)
        #expect(many.visibleLines(around: 5.2, behind: 2, ahead: 3) == 3..<9)
    }

    // Scrolling the script by hand needs the inverse of `linePosition`.
    @Test func wordPositionIsTheInverseOfLinePosition() {
        for word in [0.0, 1.0, 2.0, 4.0, 6.5, 9.0, 11.0, 12.0] {
            let line = lines.linePosition(forWord: word)
            #expect(abs(lines.wordPosition(forLine: line) - word) < 0.000_001, "word \(word)")
        }
    }

    @Test func wordPositionClampsAndHandlesNoLines() {
        #expect(lines.wordPosition(forLine: -2) == 0)
        #expect(lines.wordPosition(forLine: 99) == 12)
        #expect(TeleprompterLines.empty.wordPosition(forLine: 3) == 0)
    }
}
