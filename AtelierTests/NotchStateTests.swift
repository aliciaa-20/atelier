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
