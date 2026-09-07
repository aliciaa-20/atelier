import Foundation
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

    /// Reproduces the reversal-after-suppressed-action bug from the Phase 7
    /// final review: with unsigned (`abs()`-summed) accumulation, a net
    /// upward swipe whose `.close` action was suppressed by capabilities
    /// left enough accumulated "distance" that a single, tiny reversal
    /// sample (whose *own* sign happened to be positive) could fire
    /// `.open` — even though the gesture's real net direction never
    /// changed. Signed accumulation (deriving direction from the sign of
    /// the accumulated value, not the latest sample) fixes this: the net
    /// direction is still upward, so no action should fire at all.
    @Test func reversalAfterSuppressedActionDoesNotFireOppositeAction() {
        // .collapsed-like capabilities: open allowed, close is not.
        let collapsedLike = NotchGestureCapabilities(canOpen: true, canClose: false, canSkip: true)
        var state = NotchGestureTrackingState()

        // Swipe up (negative dy) well past threshold. The would-be action
        // is `.close`, which capabilities suppress, so `hasFired` never
        // gets set and accumulation keeps going.
        for _ in 0..<10 {
            let step = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: -20, phase: .changed, isMomentum: false),
                capabilities: collapsedLike
            )
            state = step.state
            #expect(step.action == nil)
        }
        #expect(state.hasFired == false)
        #expect(state.accumulatedDY < 0)

        // A tiny downward jitter. Net accumulated direction is still
        // firmly negative (upward) -- this must NOT fire `.open`.
        let jitter = NotchGestureInterpreter.reduce(
            state,
            delta: NotchGestureDelta(dx: 0, dy: 1, phase: .changed, isMomentum: false),
            capabilities: collapsedLike
        )

        #expect(jitter.action != .open)
        #expect(jitter.action == nil)
    }

    @Test func progressReflectsFractionOfThresholdTravelled() {
        let step = NotchGestureInterpreter.reduce(
            NotchGestureTrackingState(),
            delta: NotchGestureDelta(dx: 0, dy: 30, phase: .changed, isMomentum: false),
            capabilities: allowAll
        )

        // 30 accumulated points over a 60pt threshold.
        #expect(step.progress == 0.5)
        #expect(step.action == nil)
    }

    @Test func progressClampsAtOneOncePastThreshold() {
        // 60pt threshold; a single 100pt delta overshoots it in one step,
        // so progress must clamp to 1 rather than reporting > 1.
        let step = NotchGestureInterpreter.reduce(
            NotchGestureTrackingState(),
            delta: NotchGestureDelta(dx: 0, dy: 100, phase: .changed, isMomentum: false),
            capabilities: allowAll
        )

        #expect(step.progress == 1)
        #expect(step.action == .open)
    }

    @Test func cancelledPhaseResetsTrackingIdenticallyToEnded() {
        var state = NotchGestureTrackingState()
        for _ in 0..<3 {
            state = NotchGestureInterpreter.reduce(
                state,
                delta: NotchGestureDelta(dx: 0, dy: 10, phase: .changed, isMomentum: false),
                capabilities: allowAll
            ).state
        }

        let cancelled = NotchGestureInterpreter.reduce(
            state,
            delta: NotchGestureDelta(dx: 0, dy: 0, phase: .cancelled, isMomentum: false),
            capabilities: allowAll
        )

        #expect(cancelled.state.accumulatedDX == 0)
        #expect(cancelled.state.accumulatedDY == 0)
        #expect(cancelled.state.lockedAxis == nil)
        #expect(cancelled.state.hasFired == false)
        #expect(cancelled.action == nil)
        #expect(cancelled.progress == 0)
    }
}
