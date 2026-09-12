import Testing
@testable import Atelier

struct NotchStateTests {
    @Test func hoverStartedExpandsFromCollapsed() {
        let result = NotchStateMachine.reduce(.collapsed, on: .hoverStarted)

        #expect(result == .expanded)
    }
}

extension NotchStateTests {
    @Test func hoverEndedCollapsesFromExpandedWhenNotPlaying() {
        let result = NotchStateMachine.reduce(.expanded, on: .hoverEnded(isPlaying: false))

        #expect(result == .collapsed)
    }

    @Test func hoverEndedRestsAsPillFromExpandedWhenPlaying() {
        let result = NotchStateMachine.reduce(.expanded, on: .hoverEnded(isPlaying: true))

        #expect(result == .pill)
    }

    @Test func isPlayingChangedTrueMovesCollapsedToPill() {
        let result = NotchStateMachine.reduce(.collapsed, on: .isPlayingChanged(true))

        #expect(result == .pill)
    }

    @Test func isPlayingChangedFalseMovesPillToCollapsed() {
        let result = NotchStateMachine.reduce(.pill, on: .isPlayingChanged(false))

        #expect(result == .collapsed)
    }

    @Test func isPlayingChangedNeverInterruptsExpanded() {
        let result = NotchStateMachine.reduce(.expanded, on: .isPlayingChanged(false))

        #expect(result == .expanded)
    }

    @Test func hoverStartedExpandsFromPillToo() {
        let result = NotchStateMachine.reduce(.pill, on: .hoverStarted)

        #expect(result == .expanded)
    }
}

extension NotchStateTests {
    @Test func trackChangedPeeksFromCollapsed() {
        let result = NotchStateMachine.reduce(.collapsed, on: .trackChanged)

        #expect(result == .peeking)
    }

    @Test func trackChangedPeeksFromPill() {
        let result = NotchStateMachine.reduce(.pill, on: .trackChanged)

        #expect(result == .peeking)
    }

    @Test func trackChangedDoesNothingWhileAlreadyExpanded() {
        let result = NotchStateMachine.reduce(.expanded, on: .trackChanged)

        #expect(result == .expanded)
    }

    @Test func trackChangedDoesNothingWhileAlreadyPeeking() {
        let result = NotchStateMachine.reduce(.peeking, on: .trackChanged)

        #expect(result == .peeking)
    }

    @Test func hoverStartedDuringPeekTakesOverAsExpanded() {
        let result = NotchStateMachine.reduce(.peeking, on: .hoverStarted)

        #expect(result == .expanded)
    }

    @Test func peekTimerElapsedDecaysToPillWhenPlaying() {
        let result = NotchStateMachine.reduce(.peeking, on: .peekTimerElapsed(isPlaying: true))

        #expect(result == .pill)
    }

    @Test func peekTimerElapsedDecaysToCollapsedWhenNotPlaying() {
        let result = NotchStateMachine.reduce(.peeking, on: .peekTimerElapsed(isPlaying: false))

        #expect(result == .collapsed)
    }

    @Test func peekTimerElapsedIsNoOpIfHoverAlreadyTookOver() {
        let result = NotchStateMachine.reduce(.expanded, on: .peekTimerElapsed(isPlaying: true))

        #expect(result == .expanded)
    }
}

extension NotchStateTests {
    @Test func playbackToggledPeeksFromCollapsed() {
        let result = NotchStateMachine.reduce(.collapsed, on: .playbackToggled)

        #expect(result == .peeking)
    }

    @Test func playbackToggledPeeksFromPill() {
        let result = NotchStateMachine.reduce(.pill, on: .playbackToggled)

        #expect(result == .peeking)
    }

    @Test func playbackToggledDoesNothingWhileAlreadyExpanded() {
        let result = NotchStateMachine.reduce(.expanded, on: .playbackToggled)

        #expect(result == .expanded)
    }

    @Test func playbackToggledDoesNothingWhileAlreadyPeeking() {
        let result = NotchStateMachine.reduce(.peeking, on: .playbackToggled)

        #expect(result == .peeking)
    }
}

extension NotchStateTests {
    @Test func dragEnteredOpensShelfFromCollapsed() {
        let result = NotchStateMachine.reduce(.collapsed, on: .dragEntered)

        #expect(result == .shelf)
    }

    @Test func dragEnteredOpensShelfFromPill() {
        let result = NotchStateMachine.reduce(.pill, on: .dragEntered)

        #expect(result == .shelf)
    }

    @Test func dragEnteredDoesNothingWhileExpanded() {
        let result = NotchStateMachine.reduce(.expanded, on: .dragEntered)

        #expect(result == .expanded)
    }

    @Test func dragEnteredDoesNothingWhilePeeking() {
        let result = NotchStateMachine.reduce(.peeking, on: .dragEntered)

        #expect(result == .peeking)
    }

    @Test func dragExitedRestsAsCollapsedWhenNotPlaying() {
        let result = NotchStateMachine.reduce(.shelf, on: .dragExited(isPlaying: false))

        #expect(result == .collapsed)
    }

    @Test func dragExitedRestsAsPillWhenPlaying() {
        let result = NotchStateMachine.reduce(.shelf, on: .dragExited(isPlaying: true))

        #expect(result == .pill)
    }

    @Test func dragExitedDoesNothingOutsideShelf() {
        let result = NotchStateMachine.reduce(.expanded, on: .dragExited(isPlaying: true))

        #expect(result == .expanded)
    }

    @Test func dropCompletedStaysInShelf() {
        let result = NotchStateMachine.reduce(.shelf, on: .dropCompleted)

        #expect(result == .shelf)
    }

    @Test func hoverEndedClosesShelf() {
        let result = NotchStateMachine.reduce(.shelf, on: .hoverEnded(isPlaying: false))

        #expect(result == .collapsed)
    }
}
