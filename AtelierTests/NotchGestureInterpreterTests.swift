import Testing
@testable import Atelier

struct NotchGestureInterpreterTests {
    private let allowAll = NotchGestureCapabilities(canOpen: true, canClose: true, canSkip: true)
    private let allowNone = NotchGestureCapabilities(canOpen: false, canClose: false, canSkip: false)

    @Test func downwardSwipePastThresholdOpensWhenAllowed() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: 10, phase: .changed, isMomentum: false),
                capabilities: allowAll
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == .open)
    }

    @Test func downwardSwipeBelowThresholdProducesNoAction() {
        let step = NotchGestureInterpreter.reduce(
            NotchGestureTrackingState(),
            delta: NotchGestureDelta(dx: 0, dy: 5, phase: .changed, isMomentum: false),
            capabilities: allowAll
        )

        #expect(step.action == nil)
    }

    @Test func upwardSwipePastThresholdClosesWhenAllowed() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: -10, phase: .changed, isMomentum: false),
                capabilities: allowAll
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == .close)
    }

    @Test func rightwardSwipePastThresholdSkipsForwardWhenAllowed() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 10, dy: 0, phase: .changed, isMomentum: false),
                capabilities: allowAll
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == .skipForward)
    }

    @Test func leftwardSwipePastThresholdSkipsBackwardWhenAllowed() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: -10, dy: 0, phase: .changed, isMomentum: false),
                capabilities: allowAll
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == .skipBackward)
    }

    @Test func capabilitiesSuppressActionEvenPastThreshold() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: 10, phase: .changed, isMomentum: false),
                capabilities: allowNone
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == nil)
    }

    @Test func momentumDeltasAreNeverAccumulated() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<20 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: 10, phase: .changed, isMomentum: true),
                capabilities: allowAll
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == nil)
        #expect(state.accumulatedDY == 0)
    }

    @Test func endedPhaseResetsTracking() {
        var state = NotchGestureTrackingState()
        for _ in 0..<3 {
            state = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: 10, phase: .changed, isMomentum: false),
                capabilities: allowAll
            ).state
        }

        let ended = NotchGestureInterpreter.reduce(
            state,
            delta: NotchGestureDelta(dx: 0, dy: 0, phase: .ended, isMomentum: false),
            capabilities: allowAll
        )

        #expect(ended.state.accumulatedDY == 0)
        #expect(ended.state.hasFired == false)
    }

    @Test func diagonalSwipeWithoutDominantAxisProducesNoAction() {
        var state = NotchGestureTrackingState()
        var result: NotchGestureAction?

        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 10, dy: 10, phase: .changed, isMomentum: false),
                capabilities: allowAll
            )
            state = step.state
            if let action = step.action { result = action }
        }

        #expect(result == nil)
    }

    @Test func onlyOneActionFiresPerGesture() {
        var state = NotchGestureTrackingState()
        var fireCount = 0

        for _ in 0..<30 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: 10, phase: .changed, isMomentum: false),
                capabilities: allowAll
            )
            state = step.state
            if step.action != nil { fireCount += 1 }
        }

        #expect(fireCount == 1)
    }
}
