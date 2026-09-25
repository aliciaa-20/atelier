import Foundation

/// Owns the one script the teleprompter reads: a plain-text file in
/// Application Support. `directory` is injected (like `ShelfStore`) so
/// tests use a real temp directory instead of a mock. The script library
/// (folders + search) later grows this into `ShelfStore`'s JSON-manifest
/// shape; for now a single file is all that's needed.
@MainActor
final class ScriptStore {
    /// Posted after every successful save so the model reloads.
    static let didChange = Notification.Name("AtelierTeleprompterScriptDidChange")

    static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier", isDirectory: true)
            .appendingPathComponent("Teleprompter", isDirectory: true)
    }

    static let shared = ScriptStore(directory: ScriptStore.defaultDirectory)

    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("script.txt") }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(_ text: String) throws {
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        // `object: self` so a store's observers (and parallel tests) never
        // hear about a different store's saves.
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
