import Foundation

/// A minimal phase vocabulary so this file stays AppKit-free (no
/// `NSEvent.Phase`) — same discipline as `NotchGeometry`/`NotchState`.
/// The AppKit-side `NotchGestureModifier` (Task 4) translates real
/// `NSEvent.Phase`/`momentumPhase` into this before calling `reduce`.
enum NotchGesturePhase {
    case began, changed, ended, cancelled
}

/// One raw scroll-wheel sample, already unit-converted by the caller.
struct NotchGestureDelta {
    let dx: CGFloat
    let dy: CGFloat
    let phase: NotchGesturePhase
    let isMomentum: Bool
}

/// What the caller currently permits, computed from `NotchState` and
/// `LiveActivityContent.isExpandable` — see the design spec's Wiring
/// section. `reduce` never inspects `NotchState` itself; it only sees
/// these three booleans.
struct NotchGestureCapabilities {
    let canOpen: Bool
    let canClose: Bool
    let canSkip: Bool
}

enum NotchGestureAction: Equatable {
    case open
    case close
    case skipForward
    case skipBackward
}

enum NotchGestureAxis {
    case horizontal
    case vertical
}

/// Accumulated in-flight gesture state, mutated only via `reduce`.
struct NotchGestureTrackingState: Equatable {
    var accumulatedDX: CGFloat = 0
    var accumulatedDY: CGFloat = 0
    var lockedAxis: NotchGestureAxis?
    var hasFired = false

    init() {}
}

/// Mirrors `NotchStateMachine.reduce`'s shape: a pure function, no side
/// effects, easy to table-test. Thresholds/multipliers below start from
/// dynamicnotch's `SwipeMetrics` (`verticalThreshold = 60`,
/// `directionDominanceMultiplier` 1.15–1.25) read via `gh api` during
/// design — see the Phase 7 spec's Context section. Exact values are an
/// on-device tuning pass like every other gesture constant in this app.
enum NotchGestureInterpreter {
    /// Distance (in accumulated points) a swipe must travel on its
    /// dominant axis before it resolves to an action.
    static let threshold: CGFloat = 60

    /// How much more one axis's accumulated distance must exceed the
    /// other's before a direction is "locked" — prevents a diagonal
    /// swipe from firing either axis. Matches dynamicnotch's
    /// `directionDominanceMultiplier`.
    static let dominanceMultiplier: CGFloat = 1.2

    /// `threshold`/`dominanceMultiplier` default to the notch panel's own
    /// on-device-tuned values but are caller-overridable -- added so the
    /// lock-screen card (`LockScreenMusicCardView`) can ask for a quicker,
    /// smaller-swipe trigger of its own without retuning (and risking
    /// regressing) the notch panel's already-confirmed feel.
    static func reduce(
        _ state: NotchGestureTrackingState,
        delta: NotchGestureDelta,
        capabilities: NotchGestureCapabilities,
        threshold: CGFloat = NotchGestureInterpreter.threshold,
        dominanceMultiplier: CGFloat = NotchGestureInterpreter.dominanceMultiplier
    ) -> (state: NotchGestureTrackingState, action: NotchGestureAction?, progress: CGFloat) {
        if delta.phase == .ended || delta.phase == .cancelled {
            return (NotchGestureTrackingState(), nil, 0)
        }

        // Momentum is the coasting tail of a flick the user already let
        // go of, not new input — accumulating it double-counts the same
        // gesture. See Atoll's `PanGesture.swift` comment: "one swipe
        // skipped two tracks" was this exact bug.
        guard !delta.isMomentum else {
            return (state, nil, 0)
        }

        guard !state.hasFired else {
            return (state, nil, 0)
        }

        var next = state
        // Signed accumulation, not `abs()`-summed magnitude — a
        // back-and-forth wobble should partially cancel out in net
        // displacement, and the fired direction must come from the sign
        // of that net displacement, not from whichever way the finger
        // happened to be moving on the threshold-crossing sample. See
        // the Phase 7 final-review fix for the reversal-after-suppressed
        // -action bug this replaced.
        next.accumulatedDX += delta.dx
        next.accumulatedDY += delta.dy

        if next.lockedAxis == nil {
            let dx = abs(next.accumulatedDX)
            let dy = abs(next.accumulatedDY)
            if dx > dy * dominanceMultiplier {
                next.lockedAxis = .horizontal
            } else if dy > dx * dominanceMultiplier {
                next.lockedAxis = .vertical
            }
        }

        guard let axis = next.lockedAxis else {
            return (next, nil, 0)
        }

        let progress: CGFloat
        let action: NotchGestureAction?

        switch axis {
        case .vertical:
            progress = min(abs(next.accumulatedDY) / threshold, 1)
            if abs(next.accumulatedDY) >= threshold {
                if next.accumulatedDY > 0, capabilities.canOpen {
                    action = .open
                } else if next.accumulatedDY < 0, capabilities.canClose {
                    action = .close
                } else {
                    action = nil
                }
            } else {
                action = nil
            }
        case .horizontal:
            progress = min(abs(next.accumulatedDX) / threshold, 1)
            if abs(next.accumulatedDX) >= threshold, capabilities.canSkip {
                action = next.accumulatedDX > 0 ? .skipForward : .skipBackward
            } else {
                action = nil
            }
        }

        if action != nil {
            next.hasFired = true
        }

        return (next, action, progress)
    }
}
