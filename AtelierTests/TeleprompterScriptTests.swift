import Testing
@testable import Atelier

struct TeleprompterScriptTests {
    @Test func emptyTextHasNoWords() {
        let script = TeleprompterScript(text: "")
        #expect(script.isEmpty)
        #expect(script.wordCount == 0)
        #expect(script.paragraphs.isEmpty)
    }

    @Test func whitespaceOnlyIsEmpty() {
        let script = TeleprompterScript(text: "  \n\t\n   \n")
        #expect(script.isEmpty)
    }

    @Test func eachNonEmptyLineIsAParagraph() {
        let script = TeleprompterScript(text: "hello world\n\nsecond line here")
        #expect(script.words == ["hello", "world", "second", "line", "here"])
        #expect(script.paragraphs == [0..<2, 2..<5])
        #expect(script.wordCount == 5)
    }

    @Test func crlfAndExtraSpacesAreHandled() {
        let script = TeleprompterScript(text: "one   two\r\nthree")
        #expect(script.words == ["one", "two", "three"])
        #expect(script.paragraphs == [0..<2, 2..<3])
    }
}
