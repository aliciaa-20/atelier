import Testing
import Foundation
@testable import Atelier

@MainActor
struct ShelfStoreTests {
    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtelierShelfStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeSourceFile(named name: String, in directory: URL) -> URL {
        let url = directory.appendingPathComponent(name)
        try? "test content".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func addFileMovesIntoRootAndTracksItem() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let source = makeSourceFile(named: "note.txt", in: sourceDir)
        let store = ShelfStore(rootDirectory: root)

        try store.addFile(at: source, originalFilename: "note.txt")

        #expect(store.items.count == 1)
        let item = try #require(store.items.first)
        #expect(item.originalFilename == "note.txt")
        #expect(FileManager.default.fileExists(atPath: item.storageURL(root: root).path))
        // `addFile` moves `sourceURL` into the shelf rather than copying it --
        // its only production caller passes a throwaway staging copy it made
        // itself, so the source is expected to no longer exist afterward.
        #expect(FileManager.default.fileExists(atPath: source.path) == false)
    }

    @Test func removeDeletesFileAndDropsItem() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let source = makeSourceFile(named: "note.txt", in: sourceDir)
        let store = ShelfStore(rootDirectory: root)
        try store.addFile(at: source, originalFilename: "note.txt")
        let item = try #require(store.items.first)

        store.remove(item.id)

        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: item.storageURL(root: root).path) == false)
    }

    @Test func sweepExpiredRemovesOnlyOldItems() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let oldSource = makeSourceFile(named: "old.txt", in: sourceDir)
        let freshSource = makeSourceFile(named: "fresh.txt", in: sourceDir)
        let store = ShelfStore(rootDirectory: root, keepInterval: 60)
        try store.addFile(at: oldSource, originalFilename: "old.txt", addedAt: Date().addingTimeInterval(-120))
        try store.addFile(at: freshSource, originalFilename: "fresh.txt", addedAt: Date())

        store.sweepExpired()

        #expect(store.items.map(\.originalFilename) == ["fresh.txt"])
    }

    @Test func manifestPersistsAcrossStoreInstances() throws {
        let root = makeTempRoot()
        let sourceDir = makeTempRoot()
        let source = makeSourceFile(named: "note.txt", in: sourceDir)
        let firstStore = ShelfStore(rootDirectory: root)
        try firstStore.addFile(at: source, originalFilename: "note.txt")

        let secondStore = ShelfStore(rootDirectory: root)

        #expect(secondStore.items.map(\.originalFilename) == ["note.txt"])
    }
}
