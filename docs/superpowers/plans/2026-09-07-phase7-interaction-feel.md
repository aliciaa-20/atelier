# Phase 7 — Interaction Feel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trackpad gesture controls (swipe to open/close the notch,
horizontal swipe to skip tracks) and a tuned "jelly" open animation,
without touching `NotchState`/`NotchStateMachine`.

**Architecture:** A new pure `NotchGestureInterpreter` (unit-tested, no
AppKit) resolves raw scroll deltas into discrete actions; a new AppKit
`NotchGestureModifier` (manual-verification only) feeds it real
`NSEvent`s and calls the exact same entry points hover and the transport
buttons already call (`viewModel.handle(.hoverStarted)` /
`.handle(.hoverEnded(isPlaying:))`, `nowPlaying.next()`/`.previous()`).
Scattered inline `.spring(...)` literals get consolidated into a new
`NotchAnimations` preset struct, then the open preset's damping is tuned
on-device for a visible overshoot ("jelly" feel) — reusing the frame-size
interpolation SwiftUI already animates, no new visual layer. A new
`AtelierSettings.gesturesEnabled` toggle (mirroring
`peekOnTrackChangeEnabled`) gates the whole feature.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSEvent` local/global monitors),
Swift Testing (`import Testing`, `@Test`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-09-07-phase7-interaction-feel-design.md`

## Global Constraints

- `NotchGestureInterpreter.swift` imports only Foundation/CoreGraphics —
  no AppKit, no SwiftUI (same invariant as `NotchGeometry.swift`/
  `NotchState.swift`).
- No changes to `NotchState.swift`/`NotchStateMachine`'s existing cases or
  reducer logic — gestures call `NotchViewModel.handle(_:)` with the same
  `NotchEvent` cases hover already uses.
- Horizontal skip is discrete (`next()`/`previous()`), never a continuous
  scrub — no seek-position math anywhere in this plan.
- Momentum-phase scroll events are never accumulated into gesture tracking
  (matches both reference apps; prevents a single swipe from double-firing).
- `NotchGestureModifier` (the `NSEvent`-monitor AppKit code) is
  manual-verification only — no fabricated `NSEvent` unit tests.
- Every new spring/threshold constant gets a one-line comment citing its
  starting value's source (dynamicnotch/Atoll reference read, or "on-device
  tuning pass" once retuned).
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new files just
  need to land in the right directory (`Atelier/Notch/`, `Atelier/UI/`,
  `AtelierTests/`); no `.pbxproj` editing.

---

## Task 1: `NotchGestureInterpreter` — pure gesture resolution logic

**Files:**
- Create: `Atelier/Notch/NotchGestureInterpreter.swift`
- Test: `AtelierTests/NotchGestureInterpreterTests.swift`

**Interfaces:**
- Produces: `NotchGesturePhase` (enum: `began, changed, ended, cancelled`),
  `NotchGestureDelta` (struct: `dx: CGFloat, dy: CGFloat, phase:
  NotchGesturePhase, isMomentum: Bool`), `NotchGestureCapabilities` (struct:
  `canOpen: Bool, canClose: Bool, canSkip: Bool`), `NotchGestureAction`
  (enum: `open, close, skipForward, skipBackward`, `Equatable`),
  `NotchGestureTrackingState` (struct: `accumulatedDX: CGFloat = 0,
  accumulatedDY: CGFloat = 0, lockedAxis: NotchGestureAxis? = nil,
  hasFired: Bool = false`, `Equatable`, has a public `init()`),
  `NotchGestureAxis` (enum: `horizontal, vertical`), and
  `NotchGestureInterpreter.reduce(_:delta:capabilities:) ->
  (state: NotchGestureTrackingState, action: NotchGestureAction?, progress:
  CGFloat)` — used by Task 4 (`NotchGestureModifier`).

- [ ] **Step 1: Write the failing tests**

Create `AtelierTests/NotchGestureInterpreterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchGestureInterpreterTests`
Expected: FAIL to build — `NotchGestureInterpreter` etc. don't exist yet.

- [ ] **Step 3: Implement `NotchGestureInterpreter.swift`**

```swift
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

    static func reduce(
        _ state: NotchGestureTrackingState,
        delta: NotchGestureDelta,
        capabilities: NotchGestureCapabilities
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
        next.accumulatedDX += abs(delta.dx)
        next.accumulatedDY += abs(delta.dy)

        if next.lockedAxis == nil {
            let dx = next.accumulatedDX
            let dy = next.accumulatedDY
            if dx > dy * Self.dominanceMultiplier {
                next.lockedAxis = .horizontal
            } else if dy > dx * Self.dominanceMultiplier {
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
            progress = min(next.accumulatedDY / Self.threshold, 1)
            if next.accumulatedDY >= Self.threshold {
                if delta.dy > 0, capabilities.canOpen {
                    action = .open
                } else if delta.dy < 0, capabilities.canClose {
                    action = .close
                } else {
                    action = nil
                }
            } else {
                action = nil
            }
        case .horizontal:
            progress = min(next.accumulatedDX / Self.threshold, 1)
            if next.accumulatedDX >= Self.threshold, capabilities.canSkip {
                action = delta.dx > 0 ? .skipForward : .skipBackward
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS' -only-testing:AtelierTests/NotchGestureInterpreterTests`
Expected: PASS (all 10 tests)

- [ ] **Step 5: Commit**

```bash
git add Atelier/Notch/NotchGestureInterpreter.swift AtelierTests/NotchGestureInterpreterTests.swift
git commit -m "$(cat <<'EOF'
feat: add pure NotchGestureInterpreter for swipe resolution

Threshold-crossing, direction-dominance-lock, and momentum-discarding
logic lifted from dynamicnotch/Atoll's swipe handling, kept AppKit-free
so it's unit-testable like NotchStateMachine. Not wired up yet.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 2: `NotchAnimations` — consolidate spring presets (no behavior change)

**Files:**
- Create: `Atelier/UI/NotchAnimations.swift`
- Modify: `Atelier/Notch/NotchController.swift:181` (isPlayingChanged spring),
  `Atelier/Notch/NotchController.swift:215` (triggerPeek open spring),
  `Atelier/Notch/NotchController.swift:230` (triggerPeek decay spring)
- Modify: `Atelier/UI/NotchRootView.swift:91` (hoverStarted spring),
  `Atelier/UI/NotchRootView.swift:99` (hoverEnded spring),
  `Atelier/UI/NotchRootView.swift:131` (settle tuck),
  `Atelier/UI/NotchRootView.swift:134` (settle spring-back)

**Interfaces:**
- Produces: `NotchAnimations` (enum namespace) with static `Animation`
  properties: `open`, `close`, `peekOpen`, `peekClose`, `settleTuck`,
  `settleSpringBack` — consumed by Task 3's wiring and reused as-is by
  Task 5.

This task is a **pure refactor** — every value below is copied verbatim
from its current call site. No behavior should change; verified by the
full existing suite still passing.

- [ ] **Step 1: Create `Atelier/UI/NotchAnimations.swift`**

```swift
import SwiftUI

/// Every spring/easing curve the notch's transitions use, named and
/// centralized instead of scattered inline literals — same shape as
/// dynamicnotch's `NotchAnimations.swift` (read via `gh api` during
/// Phase 7 design), though Atelier keeps fixed values rather than
/// user-selectable presets.
///
/// `open`'s damping is deliberately lower than `close`'s — see the Phase
/// 7 spec's Section 3: the frame-size interpolation between
/// `NotchViewModel.currentSize` values is what SwiftUI already animates,
/// so an underdamped `open` produces a visible overshoot ("jelly" feel)
/// on that existing geometry, with no new `scaleEffect` layer. A
/// symmetric overshoot on `close`/`peekClose` would read as the panel
/// bouncing back open, which looks like a bug — so those stay damped.
enum NotchAnimations {
    static let open: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let close: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let peekOpen: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let peekClose: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let settleTuck: Animation = .easeOut(duration: 0.12)
    static let settleSpringBack: Animation = .spring(response: 0.35, dampingFraction: 0.5)
}
```

- [ ] **Step 2: Replace the inline springs in `NotchController.swift`**

At `NotchController.swift:181` (inside `isPlayingCancellable`'s sink,
the `else` branch that isn't peeking):

```swift
// before
withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
    viewModel.handle(.isPlayingChanged(hasContent))
}

// after
withAnimation(NotchAnimations.open) {
    viewModel.handle(.isPlayingChanged(hasContent))
}
```

At `NotchController.swift:215` (start of `triggerPeek`):

```swift
// before
withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
    viewModel.handle(event)
}

// after
withAnimation(NotchAnimations.peekOpen) {
    viewModel.handle(event)
}
```

At `NotchController.swift:230` (inside `triggerPeek`'s decay `Task`):

```swift
// before
withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
    viewModel.handle(.peekTimerElapsed(isPlaying: hasContent))
}

// after
withAnimation(NotchAnimations.peekClose) {
    viewModel.handle(.peekTimerElapsed(isPlaying: hasContent))
}
```

- [ ] **Step 3: Replace the inline springs/easing in `NotchRootView.swift`**

At `NotchRootView.swift:91` (`.onHover`'s `hovering` branch):

```swift
// before
withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
    viewModel.handle(.hoverStarted)
}

// after
withAnimation(NotchAnimations.open) {
    viewModel.handle(.hoverStarted)
}
```

At `NotchRootView.swift:99` (`.onHover`'s not-hovering branch):

```swift
// before
withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
}

// after
withAnimation(NotchAnimations.close) {
    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
}
```

At `NotchRootView.swift:131` and `:134` (`playSettleAnimation`):

```swift
// before
private func playSettleAnimation() {
    withAnimation(.easeOut(duration: 0.12)) {
        settleScale = 0.55
    }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.12)) {
        settleScale = 1
    }
}

// after
private func playSettleAnimation() {
    withAnimation(NotchAnimations.settleTuck) {
        settleScale = 0.55
    }
    withAnimation(NotchAnimations.settleSpringBack.delay(0.12)) {
        settleScale = 1
    }
}
```

- [ ] **Step 4: Build and run the full existing test suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS, same test count as before this task (no new failures —
this task only renamed values, all numbers are unchanged).

- [ ] **Step 5: Build and relaunch the app; confirm nothing looks different**

Use the `/build` slash command (builds and relaunches). Manually hover
the notch open/close, skip a track to trigger a peek, and switch Spaces
to trigger the settle animation. Every motion should look identical to
before this task — this is a pure rename, not a tuning change yet (tuning
happens in Task 6).

- [ ] **Step 6: Commit**

```bash
git add Atelier/UI/NotchAnimations.swift Atelier/Notch/NotchController.swift Atelier/UI/NotchRootView.swift
git commit -m "$(cat <<'EOF'
refactor: consolidate notch spring literals into NotchAnimations

Pure rename -- every value is unchanged, just centralized so Task 6's
jelly tuning pass has one place to edit. Precedent: dynamicnotch's own
NotchAnimations.swift, read via gh api during Phase 7 design.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 3: `gesturesEnabled` setting + menu toggle

**Files:**
- Modify: `Atelier/AtelierSettings.swift`
- Modify: `Atelier/AtelierApp.swift:35` (near the existing "Peek on Track
  Change" toggle)

**Interfaces:**
- Produces: `AtelierSettings.gesturesEnabledKey: String`,
  `AtelierSettings.gesturesEnabled: Bool` (read-only computed property,
  same shape as `peekOnTrackChangeEnabled`) — consumed by Task 5's wiring.

- [ ] **Step 1: Add the setting**

In `Atelier/AtelierSettings.swift`, add alongside the existing key/property
(mirrors `peekOnTrackChangeKey`/`peekOnTrackChangeEnabled` exactly):

```swift
enum AtelierSettings {
    static let peekOnTrackChangeKey = "peekOnTrackChangeEnabled"
    static let gesturesEnabledKey = "gesturesEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            peekOnTrackChangeKey: true,
            gesturesEnabledKey: true
        ])
    }

    static var peekOnTrackChangeEnabled: Bool {
        UserDefaults.standard.bool(forKey: peekOnTrackChangeKey)
    }

    static var gesturesEnabled: Bool {
        UserDefaults.standard.bool(forKey: gesturesEnabledKey)
    }
}
```

- [ ] **Step 2: Add the menu-bar toggle**

Read `Atelier/AtelierApp.swift` around line 35 first to see the exact
surrounding `Menu` content, then add a second `Toggle` directly below the
existing "Peek on Track Change" one, same `Binding` shape:

```swift
Toggle("Enable Gestures", isOn: Binding(
    get: { AtelierSettings.gesturesEnabled },
    set: { UserDefaults.standard.set($0, forKey: AtelierSettings.gesturesEnabledKey) }
))
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED (no tests exercise `UserDefaults`-backed
settings today, matching the existing `peekOnTrackChangeEnabled`, which
also has no dedicated test — consistent with the codebase's existing
posture on `UserDefaults` settings).

- [ ] **Step 4: Manual check**

Use `/build`, open the menu-bar item, confirm "Enable Gestures" appears
under "Peek on Track Change" and toggles.

- [ ] **Step 5: Commit**

```bash
git add Atelier/AtelierSettings.swift Atelier/AtelierApp.swift
git commit -m "$(cat <<'EOF'
feat: add gesturesEnabled setting and menu toggle

Mirrors the existing peekOnTrackChangeEnabled pattern exactly. Not
consumed anywhere yet -- NotchGestureModifier reads it in the next task.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 4: `NotchGestureModifier` — AppKit scroll-wheel monitoring

**Files:**
- Create: `Atelier/UI/NotchGestureModifier.swift`

**Interfaces:**
- Consumes: `NotchGestureInterpreter.reduce(_:delta:capabilities:)`,
  `NotchGestureTrackingState`, `NotchGestureDelta`, `NotchGesturePhase`,
  `NotchGestureCapabilities`, `NotchGestureAction` (all from Task 1).
- Produces: `NotchGestureModifier` (a `ViewModifier`) with initializer
  `init(capabilities: NotchGestureCapabilities, onOpen: @escaping () ->
  Void, onClose: @escaping () -> Void, onSkipForward: @escaping () ->
  Void, onSkipBackward: @escaping () -> Void)` — consumed by Task 5's
  `NotchRootView` wiring via `.modifier(NotchGestureModifier(...))`.

This file is **manual-verification only** per the Global Constraints —
no unit test target for it. Structurally mirrors dynamicnotch's
`NotchSwipeDismissModifier`/Atoll's `panGesture` `ScrollMonitor`
(`NSViewRepresentable` + local/global `NSEvent` monitors), credited in
the file's header comment.

- [ ] **Step 1: Implement `NotchGestureModifier.swift`**

```swift
import SwiftUI
internal import AppKit

/// Trackpad swipe detection over the notch panel. Structurally adapted
/// from jackson-storm/dynamicnotch's `NotchSwipeDismissModifier` and
/// Ebullioscopic/Atoll's `panGesture`/`ScrollMonitor` (both read via
/// `gh api` during Phase 7 design) -- local *and* global scroll-wheel
/// monitors, because the cursor may be at the very top screen edge,
/// outside the panel's own hit-testing region, when a swipe starts.
///
/// All gesture *resolution* (thresholds, direction locking, momentum
/// discarding) lives in the pure, unit-tested `NotchGestureInterpreter`;
/// this file only translates real `NSEvent`s into `NotchGestureDelta`
/// and dispatches the resulting action to a closure. Manual-verification
/// only -- no real trackpad in CI, same treatment as `AppleScriptRunner`.
struct NotchGestureModifier: ViewModifier {
    let capabilities: NotchGestureCapabilities
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void

    func body(content: Content) -> some View {
        content.background(
            NotchGestureMonitorRepresentable(
                capabilities: capabilities,
                onOpen: onOpen,
                onClose: onClose,
                onSkipForward: onSkipForward,
                onSkipBackward: onSkipBackward
            )
        )
    }
}

private struct NotchGestureMonitorRepresentable: NSViewRepresentable {
    let capabilities: NotchGestureCapabilities
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSkipForward: () -> Void
    let onSkipBackward: () -> Void

    func makeNSView(context: Context) -> NotchGestureMonitorView {
        let view = NotchGestureMonitorView()
        view.update(
            capabilities: capabilities,
            onOpen: onOpen,
            onClose: onClose,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward
        )
        return view
    }

    func updateNSView(_ nsView: NotchGestureMonitorView, context: Context) {
        nsView.update(
            capabilities: capabilities,
            onOpen: onOpen,
            onClose: onClose,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward
        )
    }

    static func dismantleNSView(_ nsView: NotchGestureMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class NotchGestureMonitorView: NSView {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private var capabilities = NotchGestureCapabilities(canOpen: false, canClose: false, canSkip: false)
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onSkipForward: (() -> Void)?
    private var onSkipBackward: (() -> Void)?

    private var trackingState = NotchGestureTrackingState()
    private var isTracking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMonitorsIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitoring()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorsIfNeeded()
    }

    func update(
        capabilities: NotchGestureCapabilities,
        onOpen: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void
    ) {
        self.capabilities = capabilities
        self.onOpen = onOpen
        self.onClose = onClose
        self.onSkipForward = onSkipForward
        self.onSkipBackward = onSkipBackward
    }

    func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        resetTracking()
    }
}

private extension NotchGestureMonitorView {
    func installMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event, screenLocation: self?.screenLocation(for: event))
                return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event, screenLocation: NSEvent.mouseLocation)
            }
        }
    }

    func screenLocation(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        }
        return NSEvent.mouseLocation
    }

    func handleScroll(_ event: NSEvent, screenLocation: NSPoint?) {
        guard AtelierSettings.gesturesEnabled else {
            resetTracking()
            return
        }
        guard event.hasPreciseScrollingDeltas else { return }
        guard let screenLocation, let screenRect = currentScreenRect() else { return }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            isTracking = screenRect.contains(screenLocation)
            trackingState = NotchGestureTrackingState()
            return
        }

        guard isTracking else { return }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            resetTracking()
            return
        }

        let delta = NotchGestureDelta(
            dx: CGFloat(event.scrollingDeltaX),
            dy: CGFloat(event.scrollingDeltaY),
            phase: .changed,
            isMomentum: !event.momentumPhase.isEmpty
        )

        let result = NotchGestureInterpreter.reduce(trackingState, delta: delta, capabilities: capabilities)
        trackingState = result.state

        switch result.action {
        case .open:
            DispatchQueue.main.async { [weak self] in self?.onOpen?() }
        case .close:
            DispatchQueue.main.async { [weak self] in self?.onClose?() }
        case .skipForward:
            DispatchQueue.main.async { [weak self] in self?.onSkipForward?() }
        case .skipBackward:
            DispatchQueue.main.async { [weak self] in self?.onSkipBackward?() }
        case nil:
            break
        }
    }

    func currentScreenRect() -> CGRect? {
        guard let window else { return nil }
        let rectInWindow = convert(bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    func resetTracking() {
        isTracking = false
        trackingState = NotchGestureTrackingState()
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED. `NotchGestureModifier` isn't attached to any
view yet (Task 5), so this step only confirms it compiles standalone.

- [ ] **Step 3: Commit**

```bash
git add Atelier/UI/NotchGestureModifier.swift
git commit -m "$(cat <<'EOF'
feat: add NotchGestureModifier for trackpad scroll-wheel monitoring

Local+global NSEvent scroll monitors scoped to the panel's screen rect,
feeding the pure NotchGestureInterpreter and dispatching resolved
actions to closures. Structurally adapted from dynamicnotch's
NotchSwipeDismissModifier and Atoll's panGesture (read via gh api).
Not wired into NotchRootView yet. Manual-verification only, per this
codebase's treatment of AppKit event plumbing.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 5: Wire gestures into `NotchRootView`

**Files:**
- Modify: `Atelier/UI/NotchRootView.swift`

**Interfaces:**
- Consumes: `NotchGestureModifier` (Task 4), `NotchGestureCapabilities`
  (Task 1), `NotchAnimations.open`/`.close` (Task 2),
  `AtelierSettings.gesturesEnabled` (Task 3), existing
  `viewModel.handle(_:)`, `liveActivity.topContent?.isExpandable`,
  `liveActivity.hasContent`, `nowPlaying.next()`/`.previous()` (all
  already present in this file/its dependencies).

- [ ] **Step 1: Add the modifier to the root `ZStack`**

In `Atelier/UI/NotchRootView.swift`, the `ZStack` currently ends with
`.onHover { ... }` (around line 89-103). Add the gesture modifier as a
sibling modifier right after `.onHover`'s closing brace, before the
`allowsHitTesting`-scoped `Spacer`:

```swift
.onHover { hovering in
    // ... existing code, unchanged ...
}
.modifier(
    AtelierSettings.gesturesEnabled
        ? NotchGestureModifier(
            capabilities: NotchGestureCapabilities(
                canOpen: viewModel.state == .collapsed || viewModel.state == .pill,
                canClose: viewModel.state == .expanded || viewModel.state == .peeking,
                canSkip: liveActivity.topContent?.isExpandable == true
            ),
            onOpen: {
                withAnimation(NotchAnimations.open) {
                    viewModel.handle(.hoverStarted)
                }
            },
            onClose: {
                withAnimation(NotchAnimations.close) {
                    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                }
            },
            onSkipForward: {
                Task { await nowPlaying.next() }
            },
            onSkipBackward: {
                Task { await nowPlaying.previous() }
            }
        )
        : NotchGestureModifier(
            capabilities: NotchGestureCapabilities(canOpen: false, canClose: false, canSkip: false),
            onOpen: {}, onClose: {}, onSkipForward: {}, onSkipBackward: {}
        )
)
```

The disabled branch still attaches an inert modifier (all-`false`
capabilities, no-op closures) rather than conditionally omitting it, so
the view identity/`background` stays stable across a settings toggle
flip — avoids tearing down and reinstalling the `NSView`'s event monitors
on every capability recompute, only on an actual settings change (SwiftUI
still reinitializes the backing view if `AtelierSettings.gesturesEnabled`
changes because `NotchRootView.body` re-evaluates on any `@Published`
change, but the closures/capabilities updating via `updateNSView` doesn't
tear down the monitors themselves — see Task 4's `updateNSView`, which
only calls `.update(...)`, not `makeNSView` again).

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Atelier -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS — no existing test touches gesture wiring, so this
confirms no regression.

- [ ] **Step 4: Manual on-device verification**

Use `/build`. With Spotify playing, work through:
1. Two-finger swipe down over the collapsed pill → notch opens
   (`.expanded`).
2. Two-finger swipe up over the expanded player → notch closes back to
   `.pill`.
3. Swipe down over the bare collapsed notch with no music playing → notch
   opens.
4. Two-finger swipe right over the pill → track skips forward. Swipe left
   → skips backward.
5. Toggle "Enable Gestures" off in the menu bar → repeat 1-4, confirm none
   of them fire, then toggle back on and confirm they resume.
6. If the Battery widget is the current top content (e.g. actually
   charging), confirm a horizontal swipe does *not* skip tracks (`canSkip`
   should be `false` since Battery's `isExpandable` is `false`).

Record the outcome of each check directly in this plan file (edit the
checkbox line to note pass/fail) before moving to Task 6.

- [ ] **Step 5: Commit**

```bash
git add Atelier/UI/NotchRootView.swift
git commit -m "$(cat <<'EOF'
feat: wire gesture controls into NotchRootView

Swipe down/up over the notch now opens/closes it (reusing the same
hoverStarted/hoverEnded events hover already dispatches); swipe
left/right skips tracks when now-playing is the active content. Gated
by AtelierSettings.gesturesEnabled. Confirmed on-device.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 6: Tune the open spring for a visible "jelly" overshoot

**Files:**
- Modify: `Atelier/UI/NotchAnimations.swift` (only the `open` and
  `peekOpen` values)

This is an on-device tuning pass, same shape as the Phase 5/6 live polish
sessions recorded in `docs/ROADMAP.md`. No test changes — the earlier
tasks' tests only assert gesture *resolution* logic, not animation curve
values, so this task is pure iteration against the running app.

- [ ] **Step 1: Lower the damping fraction**

In `Atelier/UI/NotchAnimations.swift`, change:

```swift
static let open: Animation = .spring(response: 0.35, dampingFraction: 0.8)
```

to a starting point for tuning:

```swift
static let open: Animation = .spring(response: 0.35, dampingFraction: 0.65)
```

Leave `peekOpen` at its current value for now — tune `open` first, decide
whether `peekOpen` needs the same treatment afterward (the peek pill is
much smaller, so an overshoot there may read as jittery rather than
elastic; judge on-device).

- [ ] **Step 2: Build, relaunch, and observe**

Use `/build`. Hover open the notch (and/or swipe-open, from Task 5)
several times. Compare against `close`'s motion (still damped, no
overshoot) to judge whether `open` now reads as elastic/jelly-like or as
glitchy/bouncy.

- [ ] **Step 3: Iterate on `dampingFraction` until it reads right**

Try values between roughly 0.55 (more pronounced overshoot) and 0.75
(subtle) based on step 2's result. This is a live, on-device judgment
call — there is no unit test for "looks like jelly." Update the comment
above `NotchAnimations.open` in the source file to record the final
chosen value and a one-line note on why (matches the existing pattern of
tuning comments elsewhere in this codebase, e.g. `pillExtraWidth`'s
comment in `NotchController.swift`).

- [ ] **Step 4: Decide on `peekOpen`**

Based on step 3's result, either apply the same tuned `dampingFraction` to
`peekOpen` or leave it damped — record the decision as a code comment
either way.

- [ ] **Step 5: Re-run the full test suite**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS (this task only touches animation curve constants, nothing
tests-visible).

- [ ] **Step 6: Commit**

```bash
git add Atelier/UI/NotchAnimations.swift
git commit -m "$(cat <<'EOF'
polish: tune open spring for a visible jelly overshoot

On-device tuning pass -- lowered dampingFraction on NotchAnimations.open
[/peekOpen] until the frame-size interpolation between pill/collapsed
and expanded/peeking visibly overshoots and settles, matching real
Dynamic Island motion. close/peekClose stay damped -- an overshoot there
read as the panel bouncing back open.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```

---

## Task 7: Roadmap + docs sync

**Files:**
- Modify: `docs/ROADMAP.md`

- [ ] **Step 1: Update Phase 7's entry**

Mark Phase 7's checklist items done (gesture controls, physics-based
spring/jelly morph animation), change its status marker from `⬜ planned`
to `✅ done`, and add the same kind of "what actually shipped / what was
tuned on-device" prose paragraph Phases 5/6 have — cite the final
`dampingFraction` chosen in Task 6, the discrete-skip decision, and the
`isExpandable`-gating reuse from Phase 6. Update the "Where we are" summary
at the top of the file and the "Next up" pointer to Phase 8.

- [ ] **Step 2: Update `CLAUDE.md` if any new invariant emerged**

If Task 1-6 surfaced a genuinely new invariant worth enforcing project-wide
(e.g. "gesture logic stays AppKit-free, mirroring Invariant 1"), add it to
the Invariants list in `CLAUDE.md`. If nothing rose to that level, skip
this step — don't manufacture an invariant that isn't load-bearing.

- [ ] **Step 3: Run the full test suite one last time**

Run: `xcodebuild test -scheme Atelier -destination 'platform=macOS'`
Expected: PASS, and note the new total test count (was 56 at the end of
Phase 6; Task 1 adds 10 more) in the ROADMAP entry.

- [ ] **Step 4: Commit**

```bash
git add docs/ROADMAP.md CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: sync ROADMAP.md with Phase 7's shipped interaction feel work

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0124yKTWHuLdrDfjcebwgfwU
EOF
)"
```
