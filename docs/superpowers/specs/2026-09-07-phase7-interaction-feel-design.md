# Phase 7 — Interaction feel

## Context

Phase 6 shipped `LiveActivityStack`/`LiveActivityCoordinator`, an extensible
seam for widgets, and confirmed it scales. Phase 7 is orthogonal —
`FEATURES.md §2` calls for gesture controls (swipe to open/close, horizontal
swipe to seek/skip) and physics-based spring/"jelly" morph animation. Per
`ROADMAP.md`, Phase 7 "can run in parallel with Phase 6" and has no
dependency on it, but Phase 7's skip gesture does read Phase 6's
`LiveActivityContent.isExpandable` flag as its gating signal (see below).

Sources cited in `FEATURES.md`: Atoll and dynamicnotch for gestures,
dynamicnotch for the jelly morph. Both were read directly via `gh api` per
`check-reference-apps-first` before designing:

- **Atoll** (`DynamicIsland/extensions/PanGesture.swift`,
  `ContentView.swift`): a `panGesture(direction:threshold:action:)` view
  modifier layering a `DragGesture(minimumDistance: 0)` (click-drag) behind
  an `NSViewRepresentable` scroll-wheel monitor (local + global), so both a
  physical drag and a two-finger trackpad glide drive the same action
  closure. Used four times — `.down` opens, `.up` closes (gated behind a
  separate "close gesture enabled" + "reverse scroll" setting), `.left`/
  `.right` call `musicManager.handleSkipGesture(direction:)` — a **discrete**
  next/previous, not a continuous scrub. Momentum-phase events are
  explicitly skipped, with a comment recording a real bug this fixed: "one
  swipe skipped two tracks" when momentum re-triggered the same threshold
  crossing a second time. Gestures are gated by an `enableGestures` setting.
- **dynamicnotch** (`NotchMouseSwipeModifier.swift`,
  `NotchSwipeDismissModifier.swift`, `SwipeFeedbackMetrics.swift`,
  `NotchAnimations.swift`): the same two-monitor pattern (mouse-drag +
  scroll-wheel), plus a direction-dominance lock (`directionDominanceMultiplier`)
  so a diagonal swipe can't fire both axes, plus a live 0...1 "stretch
  progress" callback used for blur/opacity feedback while the gesture is
  in flight (not an actual shape morph). `NotchAnimations.swift` centralizes
  every spring value used across the app into one preset struct
  (`.spring(response:dampingFraction:blendDuration:)` per transition)
  rather than scattering literals — this is the direct precedent for
  Section 3 below. Neither reference app morphs the notch's geometry for
  "jelly" — the elastic feel comes entirely from spring *timing*, not a
  squash/stretch transform.

**Decision, confirmed with the user across two rounds of questions:**

1. Horizontal swipe is a **discrete track skip** (next/previous), not a
   continuous seek-scrub — matches both references, far simpler.
2. Vertical swipe **supplements** hover rather than replacing it — hover
   stays the primary open/close trigger (Invariant 7 unaffected); swipe is
   an additional way to reach the same transitions, mainly for trackpad
   users who don't want to move the cursor up to the notch.
3. The skip gesture only fires when now-playing is the active content —
   gated on `LiveActivityContent.isExpandable`, which (per Phase 6's
   `LiveActivitySource.swift`) is already `true` only for now-playing.
   No new property; this is a direct reuse of an existing Phase 6 signal.
4. "Jelly" is achieved by tuning the *existing* spring architecture (lower
   damping → visible overshoot on the already-animated frame size), not by
   adding a new squash/stretch `scaleEffect` layer — see Section 3.
5. Gestures are gated by a new `AtelierSettings.gesturesEnabled` toggle,
   mirroring the existing `peekOnTrackChangeEnabled` pattern exactly.

## Non-goals

- Continuous seek-scrub via horizontal swipe.
- Vertical swipe replacing hover as the primary trigger, or any change to
  `NotchState`/`NotchStateMachine` — both stay exactly as Phase 5/6 left
  them. Gestures call the same public entry points hover already calls.
- A new anisotropic `scaleEffect` squash/stretch visual layer (see Section 3
  — deliberately not built; the existing frame-size spring is reused
  instead).
- Camera mirror mode (`FEATURES.md §2`'s third item) — separate phase
  (14), unrelated mechanism.
- Wiring `isExpandable` into the hover-to-expand gating gap the Phase 6
  ROADMAP notes left open ("Accepted and deferred") — out of scope here;
  this phase only *reads* `isExpandable`, doesn't extend its usage.
- Gesture *conflict resolution* beyond direction-dominance locking (e.g. a
  configurable sensitivity setting, reverse-scroll option) — both reference
  apps have these as user settings; Atelier ships fixed constants for now,
  same posture Phase 6 took on priority tables.

## Architecture

```
NotchController ──owns── NotchPanel
        │                    │
        │                    └── NotchRootView (SwiftUI)
        │                          └── .modifier(NotchGestureModifier)  ← new
        │
        ├── NotchGeometry            (pure)                    ← unit tested
        ├── NotchState               (pure)                    ← unit tested
        ├── NotchGestureInterpreter  (pure, new)                ← unit tested
        ├── LiveActivityStack        (pure)                     ← unit tested
        │
        ├── NotchAnimations          (UI, new — spring presets)
        └── NotchGestureModifier     (UI/AppKit, new — NSEvent monitors)
```

No new coordinator class. Gesture actions resolve to calls already made
elsewhere today: `viewModel.handle(.hoverStarted)` /
`.handle(.hoverEnded(isPlaying:))` (same as `NotchRootView.onHover`), and
`nowPlayingCoordinator.next()` / `.previous()` (same as the transport
buttons in `ExpandedPlayerView`).

## `NotchGestureInterpreter` — pure, unit-tested

`Atelier/Notch/NotchGestureInterpreter.swift`. Foundation/CoreGraphics only
— same invariant as `NotchGeometry`/`NotchState`: no AppKit import, so it
doesn't touch `NSEvent.Phase` directly. Defines its own minimal phase
vocabulary instead:

```swift
enum NotchGesturePhase {
    case began, changed, ended, cancelled
}

struct NotchGestureDelta {
    let dx: CGFloat
    let dy: CGFloat
    let phase: NotchGesturePhase
    let isMomentum: Bool
}

/// What the current NotchState/content permit right now — computed by the
/// caller from `viewModel.state` and `liveActivity.topContent?.isExpandable`.
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

/// Accumulated in-flight gesture state — mutated only via `reduce`.
struct NotchGestureTrackingState: Equatable {
    var accumulatedDX: CGFloat = 0
    var accumulatedDY: CGFloat = 0
    var lockedAxis: Axis? = nil   // nil until dominance is determined
    var hasFired = false           // one action per gesture, like the references
}

enum NotchGestureInterpreter {
    /// Mirrors NotchStateMachine.reduce's shape: pure function, no side
    /// effects. Momentum deltas are discarded entirely (never accumulated)
    /// per the "one swipe skipped two tracks" bug both references guard
    /// against. `.ended`/`.cancelled` always resets tracking.
    static func reduce(
        _ state: NotchGestureTrackingState,
        delta: NotchGestureDelta,
        capabilities: NotchGestureCapabilities
    ) -> (state: NotchGestureTrackingState, action: NotchGestureAction?, progress: CGFloat)
}
```

Threshold and dominance-multiplier constants live as `static let`s next to
this enum, named and commented with the values pulled from the reference
read (starting point: dynamicnotch's `verticalThreshold = 60`,
`directionDominanceMultiplier` in the 1.15–1.25 range) — exact numbers are
an on-device tuning pass, same as every other gesture/animation constant in
this codebase (`pillExtraWidth`, `peekDuration`, etc.).

`progress` is a live 0...1 value on the dominant axis while the gesture is
in flight, resetting to 0 on axis-lock loss or gesture end — available for
future visual feedback but not consumed by anything in this phase (no
blur/opacity layer is being built — see Non-goals).

## `NotchGestureModifier` — AppKit, manual-only

`Atelier/UI/NotchGestureModifier.swift`. An `NSViewRepresentable` +
backing `NSView`, structurally mirroring `NotchMouseSwipeModifier`/
`panGesture` (credited in a source comment). Installs local *and* global
`NSEvent.addMonitorForEvents(matching: .scrollWheel)` monitors — global is
necessary because the cursor may be at the very top screen edge, outside
the panel's own hit-testing region, when the gesture starts (same reasoning
as Atoll's `verticalEdgeInset`). Converts each `NSEvent` into a
`NotchGestureDelta` (reading `scrollingDeltaX/Y`, `phase`, `momentumPhase`)
and feeds `NotchGestureInterpreter.reduce`, translating a resolved
`NotchGestureAction` into the corresponding closure call
(`onOpen`/`onClose`/`onSkipForward`/`onSkipBackward`).

Scoped to the notch's on-screen rect the same way `NotchSwipeDismissMonitorView`
computes `currentScreenRect()` — converts the view's bounds to screen space
via its window, so it tracks the actual panel position rather than a fixed
screen coordinate.

Per Atelier's testing conventions, this file is **manual-verification
only** — no fake `NSEvent` construction, matching how `AppleScriptRunner`
and `IOBluetoothDevice` integration are already treated.

## Section 3 — Animation consolidation + jelly tuning

`Atelier/UI/NotchAnimations.swift` (new): a static-preset struct collecting
every `.spring(response:dampingFraction:)` literal currently inline in
`NotchController.swift` (`triggerPeek`'s open/decay springs) and
`NotchRootView.swift` (`onHover`'s open/close springs, `playSettleAnimation`'s
tuck/spring-back), following dynamicnotch's `NotchAnimations` precedent:

```swift
enum NotchAnimations {
    static let open: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let close: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let peekOpen: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    static let peekClose: Animation = .spring(response: 0.55, dampingFraction: 0.92)
    static let settleTuck: Animation = .easeOut(duration: 0.12)
    static let settleSpringBack: Animation = .spring(response: 0.35, dampingFraction: 0.5)
}
```

Step 1 is a pure refactor — same numeric values, just named and centralized,
with every call site in `NotchController`/`NotchRootView` switched over.
No behavior change; verified by the existing test suite continuing to pass
and an on-device sanity check that nothing looks different.

Step 2 is an on-device tuning pass (same shape as Phase 5/6's live polish
sessions): lower `NotchAnimations.open`'s `dampingFraction` until the
frame's width/height interpolation — which SwiftUI already animates
independently per dimension between the four `NotchViewModel.currentSize`
values — visibly overshoots and settles, producing the "jelly" feel
without any new geometry, `scaleEffect`, or state. Gesture-triggered opens
reuse this exact same preset, so a swipe-open and a hover-open feel
identical. The close/decay presets stay damped (no overshoot) — matches
both references, where only the *open* motion reads as elastic; a
close/decay overshoot would look like the panel bouncing back open, which
reads as a bug, not a feature.

## Settings

`AtelierSettings.swift`: add

```swift
static let gesturesEnabledKey = "gesturesEnabled"
static var gesturesEnabled: Bool {
    UserDefaults.standard.bool(forKey: gesturesEnabledKey)
}
```

registered default `true` in `registerDefaults()`, alongside
`peekOnTrackChangeKey`. `AtelierApp.swift` gets a second `Toggle("Enable
Gestures", ...)` in the same menu-bar menu, same `Binding` pattern as the
existing "Peek on Track Change" toggle.

`NotchGestureModifier` is only attached/active when
`AtelierSettings.gesturesEnabled` is `true` — checked the same way
`triggerPeek` already checks `AtelierSettings.peekOnTrackChangeEnabled`.

## Wiring

In `NotchRootView.swift`, alongside the existing `.onHover { ... }` on the
root `ZStack`, add:

```swift
.modifier(NotchGestureModifier(
    capabilities: NotchGestureCapabilities(
        canOpen: viewModel.state == .collapsed || viewModel.state == .pill,
        canClose: viewModel.state == .expanded || viewModel.state == .peeking,
        canSkip: liveActivity.topContent?.isExpandable == true
    ),
    onOpen: { withAnimation(NotchAnimations.open) { viewModel.handle(.hoverStarted) } },
    onClose: { withAnimation(NotchAnimations.close) { viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent)) } },
    onSkipForward: { Task { await nowPlaying.next() } },
    onSkipBackward: { Task { await nowPlaying.previous() } }
))
```

exact call sites TBD at implementation time (may live in `NotchController`
instead if capability computation reads more naturally there) — this is
illustrative of the shape, not a literal diff.

## Testing

- `NotchGestureInterpreterTests.swift` — new, table-driven like
  `NotchStateTests`: threshold crossing per axis, direction-dominance lock
  (diagonal swipe fires neither/only-dominant), momentum deltas never
  accumulate, `.ended`/`.cancelled` resets tracking, capability gating
  (`canOpen`/`canClose`/`canSkip` false suppresses the corresponding
  action even past threshold), one-action-per-gesture (`hasFired`).
- `NotchGestureModifier` — manual-verification only, explicitly documented
  as such (real trackpad, real notch).
- Existing `NotchStateTests`/`NotchViewModel` behavior unaffected — no
  changes to what they cover, since gestures call existing public methods.
- On-device manual checklist: swipe-open from pill, swipe-close from
  expanded, swipe-open from collapsed (no music), horizontal skip during
  playback, horizontal skip attempted while Battery is the top content
  (must no-op), gesture vs. hover interaction (does a swipe mid-hover
  behave sanely), gestures-disabled setting actually suppresses all of the
  above, and the tuned open overshoot reads as "jelly" rather than
  "glitchy."

## Migration

No existing behavior changes unless a gesture fires — hover-driven
open/close, peek-on-track-change, and the Battery pill are all unaffected.
The Section 3 animation consolidation is designed to be a no-op until the
Step 2 tuning pass intentionally changes the open preset's damping.
