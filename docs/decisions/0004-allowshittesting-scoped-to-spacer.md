# ADR 0004 — `allowsHitTesting(false)` must be scoped to the Spacer, not the whole root VStack

- **Status:** Accepted
- **Date:** 2026-09-02

## Context

Phase 4 added real controls (transport buttons, a draggable scrubber) to the
expanded player. They never responded to clicks — not on the first click,
not on any click. ADR 0003 fixed a real, separate bug (`canBecomeKey`/
`acceptsFirstMouse`) but controls still didn't respond afterward.

## Investigation

Two plausible-looking fixes were tried and ruled out first:

1. **A manual `panel?.makeKey()` call in `NotchController`**, added on state
   `== .expanded`, looked like a reasonable belt-and-braces addition. Removed
   after comparing against Atoll's `DynamicIslandWindow`/`DynamicIslandApp`,
   which never calls `makeKey()` on its notch window (only
   `orderFrontRegardless()`). Controls still didn't respond — this wasn't it.
2. Atelier's `HoverTrackingView` (a custom `NSTrackingArea`-based
   `NSViewRepresentable`) was replaced with plain SwiftUI `.onHover`, matching
   how both boring.notch and Atoll implement notch hover — neither uses a
   custom tracking view or a `hitTest` override anywhere in their notch
   content. This *broke hover entirely*, which was the real signal: hover had
   worked since Phase 2 using the AppKit-level `NSTrackingArea` mechanism,
   which fires independently of SwiftUI's hit-testing pipeline. Plain
   `.onHover`, like `Button` taps, routes through SwiftUI's own hit-testing —
   and that pipeline was broken for reasons unrelated to which hover
   mechanism was in use.

The actual cause: `NotchRootView`'s root `VStack` had
`.allowsHitTesting(false)` applied to itself (to keep the large invisible
frame around the notch, needed for top-alignment, from swallowing clicks
meant for whatever app is behind it — Invariant 4). The `ZStack` containing
the actual notch/player content, nested *inside* that VStack, separately set
`.allowsHitTesting(true)` on itself. In SwiftUI, an ancestor's `false`
overrides a descendant's `true` — it does not compose the other way. So the
entire notch/player subtree was hit-testing-disabled for anything routed
through SwiftUI (buttons, scrubber, `.onHover`) from the moment Phase 4
tried to use it. The old `NSTrackingArea`-based hover from Phase 2/3 worked
by accident: it doesn't participate in SwiftUI's `allowsHitTesting`
environment at all, so it kept working right through this bug while the
buttons added in Phase 4 never had a chance.

## Decision

Scope `.allowsHitTesting(false)` to the `Spacer` alone — the actual
dead-space region that needs to not swallow clicks — instead of the `VStack`
that wraps both the Spacer and the real content:

```swift
Spacer(minLength: 0)
    .allowsHitTesting(false)
```

removed from the outer `VStack`. The `ZStack`'s own `.allowsHitTesting(true)`
becomes redundant (it's the default) but is left implicit rather than
explicit now that nothing above it overrides it.

Plain SwiftUI `.onHover` (matching boring.notch/Atoll) replaces the old
`HoverTrackingView`/`NSTrackingArea` approach; that file was deleted. With
the real bug fixed, there's no remaining reason to keep the AppKit-level
workaround.

## Consequences

- Buttons, the scrubber, and hover all respond correctly — confirmed
  on-device by the project owner.
- `HoverTrackingView.swift` is gone; `NotchRootView.swift` is simpler.
- **Lesson for future AppKit/SwiftUI debugging in this project:** when a
  SwiftUI-routed interaction (tap, hover, drag) silently does nothing while
  an AppKit-routed one works fine in the same view, suspect the
  `allowsHitTesting` environment chain before suspecting window-level
  (`NSPanel`) state — they're independent hit-testing systems, and a bug in
  one can look identical to a bug in the other from the outside.
