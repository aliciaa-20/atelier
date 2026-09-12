import Testing
import Foundation
@testable import Atelier

struct ShelfItemTests {
    private static let keepInterval: TimeInterval = 60 * 60 * 24 // 24h

    @Test func isNotExpiredJustAfterAdding() {
        let now = Date()
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: now)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == false)
    }

    @Test func isNotExpiredJustUnderTheInterval() {
        let addedAt = Date()
        let now = addedAt.addingTimeInterval(Self.keepInterval - 1)
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: addedAt)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == false)
    }

    @Test func isExpiredJustOverTheInterval() {
        let addedAt = Date()
        let now = addedAt.addingTimeInterval(Self.keepInterval + 1)
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: addedAt)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == true)
    }

    @Test func isNotExpiredIfNowIsBeforeAddedAt() {
        // Defensive: a clock adjustment shouldn't retroactively expire a
        // just-added item.
        let addedAt = Date()
        let now = addedAt.addingTimeInterval(-10)
        let item = ShelfItem(id: UUID(), originalFilename: "a.txt", addedAt: addedAt)

        #expect(item.isExpired(now: now, keepInterval: Self.keepInterval) == false)
    }

    @Test func storageURLNestsUnderIDThenFilename() {
        let id = UUID()
        let item = ShelfItem(id: id, originalFilename: "report.pdf", addedAt: Date())
        let root = URL(fileURLWithPath: "/tmp/AtelierShelfTest")

        let url = item.storageURL(root: root)

        #expect(url == root.appendingPathComponent(id.uuidString).appendingPathComponent("report.pdf"))
    }
}
