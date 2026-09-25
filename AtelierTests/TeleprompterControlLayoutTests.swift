import Testing
@testable import Atelier

struct TeleprompterControlLayoutTests {
    @Test func emptyStoredOrderGivesTheDefaultLayout() {
        let layout = TeleprompterControlLayout.resolve(stored: [])
        #expect(layout.left == [.play, .speed])
        #expect(layout.right == [.ring, .voice])
    }

    @Test func followsTheStoredOrderAndSplitsAtTheNotch() {
        let layout = TeleprompterControlLayout.resolve(stored: ["ring", "notch", "speed", "play"])
        // Each side holds at most two controls, so the marker is pulled to 2 | 2.
        #expect(layout.left == [.ring, .speed])
        #expect(layout.right == [.play, .voice])
    }

    @Test func unknownNamesAndDuplicatesAreIgnored() {
        let layout = TeleprompterControlLayout.resolve(stored: ["bogus", "speed", "speed", "play", "notch", "ring"])
        #expect(layout.left == [.speed, .play])
        #expect(layout.right == [.ring, .voice])
    }

    @Test func controlsMissingFromTheStoredListAreAppended() {
        let layout = TeleprompterControlLayout.resolve(stored: ["ring", "notch"])
        // ring | (notch already last: clamped so each side has a control)
        #expect(layout.left.count + layout.right.count == 4)
        #expect(Set(layout.left + layout.right) == Set(TeleprompterControl.allCases))
        #expect(!layout.left.isEmpty && !layout.right.isEmpty)
    }

    @Test func theNotchNeverLeavesASideEmpty() {
        let atStart = TeleprompterControlLayout.resolve(stored: ["notch", "play", "speed", "ring"])
        #expect(!atStart.left.isEmpty && !atStart.right.isEmpty)
        let atEnd = TeleprompterControlLayout.resolve(stored: ["play", "speed", "ring", "notch"])
        #expect(!atEnd.left.isEmpty && !atEnd.right.isEmpty)
    }

    @Test func normalizedAlwaysListsAllFiveRowsWithTheNotchInTheMiddle() {
        for stored in [[], ["notch"], ["ring", "play"], ["x", "notch", "notch"]] {
            let order = TeleprompterControlLayout.normalized(stored)
            #expect(order.count == 5)
            #expect(Set(order) == ["play", "speed", "ring", "voice", "notch"])
            #expect(order.firstIndex(of: "notch") == 2)
        }
    }

    @Test func movingARowDownPutsItAfterTheTarget() {
        let order = TeleprompterControlLayout.move("play", onto: "notch", in: ["play", "speed", "notch", "ring"])
        #expect(order == ["speed", "play", "notch", "ring", "voice"])
        let layout = TeleprompterControlLayout.resolve(stored: order)
        #expect(Set(layout.left + layout.right) == Set(TeleprompterControl.allCases))
    }

    @Test func movingARowUpPutsItBeforeTheTarget() {
        let order = TeleprompterControlLayout.move("ring", onto: "play", in: ["play", "speed", "notch", "ring"])
        #expect(order.first == "ring")
        #expect(order.count == 5)
    }

    @Test func anOrderSavedBeforeVoiceSyncGetsTheNewControlAppended() {
        let layout = TeleprompterControlLayout.resolve(stored: ["play", "speed", "notch", "ring"])
        #expect(layout.left == [.play, .speed])
        #expect(layout.right == [.ring, .voice])
    }

    @Test func movingOntoItselfOrAnUnknownRowChangesNothing() {
        let start = ["play", "speed", "notch", "ring", "voice"]
        #expect(TeleprompterControlLayout.move("play", onto: "play", in: start) == start)
        #expect(TeleprompterControlLayout.move("nope", onto: "play", in: start) == start)
    }
}
