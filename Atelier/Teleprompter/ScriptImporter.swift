import AppKit

/// Turns a dropped/picked file into plain script text. `.txt`/`.md` are
/// read directly (Markdown syntax stripped); `.rtf`/`.doc`/`.docx` go
/// through `NSAttributedString`'s document importer, which is why no
/// third-party dependency is needed. Manual-verification only for real
/// Word files; the text and RTF paths are unit-tested.
enum ScriptImporter {
    static let supportedExtensions: Set<String> = ["txt", "md", "markdown", "rtf", "doc", "docx"]

    enum ImportError: Error, Equatable {
        case unsupportedType(String)
        case unreadable
        case empty

        /// Shown in the Settings pane.
        var message: String {
            switch self {
            case .unsupportedType: "Only .txt, .md, .doc, .docx and .rtf files work here"
            case .unreadable: "Couldn't read that file"
            case .empty: "That file has no text in it"
            }
        }
    }

    static func importText(from url: URL) throws -> String {
        // A dropped web link would otherwise be read over the network.
        guard url.isFileURL else { throw ImportError.unreadable }
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw ImportError.unsupportedType(ext) }

        let raw: String
        switch ext {
        case "txt": raw = try readPlain(url)
        case "md", "markdown": raw = stripMarkdown(try readPlain(url))
        default: raw = try readRich(url, ext: ext)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        return trimmed
    }

    /// The Latin-1 fallback decodes any bytes, so a binary file (or UTF-16
    /// without a BOM) would otherwise import as garbage. Real scripts have
    /// no NULs and almost no control characters.
    private static func looksBinary(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let allowed: Set<UInt32> = [0x09, 0x0A, 0x0D]
        let control = scalars.filter { $0.value < 0x20 && !allowed.contains($0.value) }.count
        return text.contains("\0") || Double(control) / Double(scalars.count) > 0.05
    }

    private static func readPlain(_ url: URL) throws -> String {
        let text = try decodePlain(url)
        if looksBinary(text) { throw ImportError.unreadable }
        return text
    }

    private static func decodePlain(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        // `usedEncoding` only recognises BOM-marked files (UTF-16 etc.), so
        // plain legacy text needs explicit fallbacks: Windows-1252 is what
        // most non-UTF-8 text files from Windows/Word are, and Latin-1
        // accepts any byte sequence as the last resort.
        var used = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &used) { return text }
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            if let text = try? String(contentsOf: url, encoding: encoding) { return text }
        }
        throw ImportError.unreadable
    }

    private static func readRich(_ url: URL, ext: String) throws -> String {
        let type: NSAttributedString.DocumentType = switch ext {
        case "rtf": .rtf
        case "doc": .docFormat
        default: .officeOpenXML
        }
        guard let attributed = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil) else {
            throw ImportError.unreadable
        }
        return attributed.string
    }

    /// Light Markdown stripping: this is text to read aloud, not to render.
    /// Keeps content, drops the syntax around it.
    static func stripMarkdown(_ text: String) -> String {
        var inFence = false
        var out: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { out.append(rawLine); continue }
            if trimmed.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { continue }

            var line = rawLine
            line = line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s*([-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(\*\*|__)(.+?)\1"#, with: "$2", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
            // Underscore emphasis only at word edges, so snake_case survives.
            line = line.replacingOccurrences(of: #"(?<!\w)_(.+?)_(?!\w)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "`", with: "")
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
