import Testing
@testable import Atelier

struct LiveActivityStackTests {
    @Test func topIDIsNilWhenEmpty() {
        let stack = LiveActivityStack()
        #expect(stack.topID == nil)
    }

    @Test func singleUpsertBecomesTop() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        #expect(stack.topID == "battery")
    }

    @Test func higherPriorityWins() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.upsert(id: "nowPlaying", priority: 5)
        #expect(stack.topID == "nowPlaying")
    }

    @Test func lowerPriorityDoesNotDisplaceTop() {
        var stack = LiveActivityStack()
        stack.upsert(id: "nowPlaying", priority: 5)
        stack.upsert(id: "battery", priority: 1)
        #expect(stack.topID == "nowPlaying")
    }

    @Test func upsertReplacesSameIDInPlace() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.upsert(id: "battery", priority: 9)
        stack.upsert(id: "nowPlaying", priority: 5)
        #expect(stack.topID == "battery")
    }

    @Test func removeDropsEntryAndPromotesNext() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.upsert(id: "nowPlaying", priority: 5)
        stack.remove(id: "nowPlaying")
        #expect(stack.topID == "battery")
    }

    @Test func removeUnknownIDIsNoOp() {
        var stack = LiveActivityStack()
        stack.upsert(id: "battery", priority: 1)
        stack.remove(id: "nowPlaying")
        #expect(stack.topID == "battery")
    }

    @Test func equalPriorityBreaksTieByIDOrdering() {
        var stackA = LiveActivityStack()
        stackA.upsert(id: "battery", priority: 1)
        stackA.upsert(id: "airpods", priority: 1)

        var stackB = LiveActivityStack()
        stackB.upsert(id: "airpods", priority: 1)
        stackB.upsert(id: "battery", priority: 1)

        // Deterministic regardless of insertion order.
        #expect(stackA.topID == stackB.topID)
    }
}
