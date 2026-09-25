import Testing
import AppKit
@testable import Atelier

struct ScriptImporterTests {
    private func tempFile(_ name: String, data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierImporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test func plainTextIsReadAndTrimmed() throws {
        let url = try tempFile("a.txt", data: Data("  Hello there\nsecond line \n\n".utf8))
        #expect(try ScriptImporter.importText(from: url) == "Hello there\nsecond line")
    }

    @Test func markdownIsStrippedToSpeakableText() throws {
        let md = "# Title\n\n**Bold** and *italic* with [a link](http://x.com).\n- item one\n1. item two\n"
        let url = try tempFile("a.md", data: Data(md.utf8))
        let text = try ScriptImporter.importText(from: url)
        #expect(text == "Title\n\nBold and italic with a link.\nitem one\nitem two")
    }

    @Test func markdownKeepsSnakeCaseAndDropsFencesAndRules() {
        let md = "use my_var_name here\n```\ncode line\n```\n---\nend"
        #expect(ScriptImporter.stripMarkdown(md) == "use my_var_name here\ncode line\nend")
    }

    @Test func rtfRoundTrips() throws {
        let attributed = NSAttributedString(string: "Rich text script")
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let url = try tempFile("a.rtf", data: data)
        #expect(try ScriptImporter.importText(from: url) == "Rich text script")
    }

    // Review Focus 5: bad files raise a specific error and never crash.
    @Test func unsupportedExtensionIsRejected() throws {
        let url = try tempFile("a.pdf", data: Data("x".utf8))
        #expect(throws: ScriptImporter.ImportError.unsupportedType("pdf")) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func emptyFileIsRejected() throws {
        let url = try tempFile("a.txt", data: Data("  \n\n".utf8))
        #expect(throws: ScriptImporter.ImportError.empty) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func nonUTF8TextFallsBackToDetectedEncoding() throws {
        // "café script" in ISO Latin-1: the 0xE9 byte is invalid UTF-8.
        let url = try tempFile("a.txt", data: Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74]))
        let text = try ScriptImporter.importText(from: url)
        #expect(text.hasSuffix("script"))
    }

    @Test func missingFileIsUnreadable() {
        let url = URL(fileURLWithPath: "/nonexistent/atelier-\(UUID().uuidString).txt")
        #expect(throws: ScriptImporter.ImportError.unreadable) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func brokenDocxIsUnreadableNotACrash() throws {
        let url = try tempFile("a.docx", data: Data("not a zip".utf8))
        #expect(throws: ScriptImporter.ImportError.unreadable) {
            try ScriptImporter.importText(from: url)
        }
    }


    // Tidy-up: the Latin-1 fallback decodes any bytes, so binary-looking
    // files (or UTF-16 without a BOM) must be refused, not imported as garbage.
    @Test func binaryLookingFileIsUnreadable() throws {
        let url = try tempFile("a.txt", data: Data([0x50, 0x00, 0x4B, 0x00, 0x03, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x02]))
        #expect(throws: ScriptImporter.ImportError.unreadable) {
            try ScriptImporter.importText(from: url)
        }
    }

    @Test func aWebLinkIsNeverReadOverTheNetwork() {
        let url = URL(string: "https://example.com/notes.txt")!
        #expect(throws: ScriptImporter.ImportError.unreadable) {
            try ScriptImporter.importText(from: url)
        }
    }
}
