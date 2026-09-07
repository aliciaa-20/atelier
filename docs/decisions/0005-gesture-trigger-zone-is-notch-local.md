# ADR 0005 — the gesture trigger zone is notch-local, not screen-wide

- **Status:** Accepted
- **Date:** 2026-09-07

## Context

Phase 7 added trackpad gesture controls: a two-finger swipe down/up over the
notch opens/closes it, and swipe left/right skips tracks. The design spec's
own framing for why swipe supplements hover said it's "mainly useful for
trackpad users who don't want to move the cursor up to the notch."

`NotchGestureModifier`'s backing `NSView` only starts tracking a gesture
(`isTracking = true`) when the cursor is inside `currentScreenRect()` at the
gesture's `.began`/`.mayBegin` phase — i.e. the swipe has to start with the
cursor already over the physical notch's on-screen bounds, the same region
`.onHover` already requires.

The final whole-branch review (Phase 7) flagged this as a possible
contradiction: if the whole point of the gesture is to avoid moving the
cursor to the notch, why does the gesture still require the cursor to be at
the notch to register?

## Investigation

Re-checked both reference apps read via `gh api` during Phase 7's design
(`check-reference-apps-first`):

- **dynamicnotch**'s `NotchSwipeDismissModifier`/`NotchMouseSwipeModifier`
  gate identically — `currentScreenRect()?.contains(screenLocation)` at
  gesture start, same panel-bounds check this codebase built.
- **Atoll**'s `PanGesture.swift` does the same, with only a small
  `verticalEdgeInset: CGFloat = 4` — enough for the cursor to "kiss" the
  very top of the screen (where the real hardware notch has zero display
  pixels of its own), not a wide capture zone reaching down into the menu
  bar or beyond.

Neither shipped reference app lets a swipe register from anywhere on
screen. Both scope it to the same region hover already uses.

## Decision

Keep the gesture trigger zone notch-local, matching both references —
**no widening.** The spec's "don't want to move the cursor up to the
notch" phrasing is read as: a decisive swipe triggers the transition
*instantly*, versus hover's passive dwell-then-trigger — not as "works
from anywhere on the screen." Hover itself already requires the cursor at
the notch; a gesture that supplements hover naturally shares hover's own
trigger region rather than inventing a wider one hover doesn't have.

No code change. `NotchGestureModifier.swift` already matches this
decision as originally implemented.

## Consequences

- A user expecting to swipe from mid-screen will find nothing happens —
  this is intentional, not a bug, and matches both the shipped references
  and this app's own hover behavior.
- If real on-device use (still pending — see `docs/ROADMAP.md`'s Phase 7
  verification note) reveals people genuinely expect a wider capture zone,
  it's a cheap follow-up: widen `NotchGestureModifier`'s screen-rect check
  (e.g. an inset like Atoll's), not an architectural change.
