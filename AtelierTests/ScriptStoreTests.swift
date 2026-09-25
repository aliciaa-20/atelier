import Testing
import Foundation
@testable import Atelier

@MainActor
struct ScriptStoreTests {
    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierScriptStoreTests-\(UUID().uuidString)")
    }

    @Test func loadOfMissingScriptIsEmpty() {
        #expect(ScriptStore(directory: makeTempDir()).load() == "")
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = ScriptStore(directory: makeTempDir())
        try store.save("Line one\nLine two")
        #expect(store.load() == "Line one\nLine two")
    }

    @Test func aFreshStoreOnTheSameDirectoryReadsTheSavedScript() throws {
        let dir = makeTempDir()
        try ScriptStore(directory: dir).save("persisted")
        #expect(ScriptStore(directory: dir).load() == "persisted")
    }

    @Test func savePostsDidChange() throws {
        let store = ScriptStore(directory: makeTempDir())
        var fired = false
        let token = NotificationCenter.default.addObserver(forName: ScriptStore.didChange, object: store, queue: nil) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }
        try store.save("x")
        #expect(fired)
    }
}
