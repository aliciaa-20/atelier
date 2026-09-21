# ADR 0013 — lock-screen card: per-caller gesture tuning, public-API-only glass

- **Status:** Accepted
- **Date:** 2026-09-22

## Context

The lock-screen now-playing card (`LockScreenMusicCardView`, ADR 0010) picked
up three features in one session: `MarqueeText` for title/artist, swipe-to-
skip, and a stronger "liquid glass" look on request ("make gestures more
quicker and responsive. make the glass effect more glass-like"). The
gesture and glass pieces each involved a choice between two real
alternatives.

## Decision 1 — gesture tuning is per-caller, not a shared constant change

Swipe-to-skip reuses the notch panel's own `NotchGestureInterpreter.reduce`
+ `NotchGestureModifier` pair (ADR 0005) — both are already window-agnostic:
`reduce` is pure Foundation-only math, and the modifier reads its own
view's screen rect rather than the notch's global position, so attaching it
to a different window's SwiftUI tree was a direct reuse, not a rewrite.

The requested "quicker and more responsive" feel meant a smaller
`threshold` (distance-to-trigger) and `dominanceMultiplier` (axis-lock
speed) than the notch panel's on-device-tuned `60pt` / `1.2x`. Two options:

1. Lower `NotchGestureInterpreter.threshold`/`dominanceMultiplier`
   directly — these are shared `static let`s, so this would also retune
   the notch panel's own swipe-open/close/skip gestures, which are already
   confirmed correct on real hardware (see the Phase 7 entries in
   `docs/ROADMAP.md`).
2. Make `reduce` and `NotchGestureModifier` accept optional
   `threshold`/`dominanceMultiplier`, defaulting to the existing statics,
   and pass tighter values only from the lock-screen card's own call site.

Went with (2): `reduce(_:delta:capabilities:threshold:dominanceMultiplier:)`
now takes two additional parameters defaulted to
`NotchGestureInterpreter.threshold`/`.dominanceMultiplier`, and
`NotchGestureModifier` threads an optional pair of the same name through to
it. The lock-screen card passes `threshold: 32, dominanceMultiplier: 1.1`;
`NotchRootView`'s existing call site is untouched and still gets the
notch's original values by omitting them.

## Decision 2 — glass technique adapted from Sapphire, minus its private API

`cshariq/Sapphire`'s `LockScreenWidgetSurface`/`LiquidGlassView.swift` (read
via `gh api`) implements "liquid glass" two ways:

- A **public-API path**: standard SwiftUI gradient fills (a diagonal sheen,
  a radial highlight pooled toward the light source) plus a gradient
  `strokeBorder` for the rim — all ordinary `LinearGradient`/`RadialGradient`
  shapes, no private surface area.
- A **private-API path**: an `NSGlassEffectView`-backed material, configured
  via `objc_msgSend` calls to undocumented selectors (`_setPath:`,
  `set_variant:`, `set_interactionState:`, etc.) for the actual translucent
  system-glass sampling.

Only the first was adopted. Two independent reasons ruled out the second:

1. `LockScreenMusicCardView`'s own type doc already argues against stacking
   a second glass material on top of the artwork-blur background (would be
   glass-on-glass, which Liquid Glass's own design rules call incorrect) —
   the private-API path exists specifically to add that second material.
2. Undocumented `objc_msgSend`-driven selectors are inherently more fragile
   across macOS point releases than public gradient/shape APIs, for a
   personal single-machine app where that risk buys nothing the public path
   doesn't already deliver visually.

`GlassHighlightOverlay` (new, in `LockScreenMusicCardView.swift`) implements
the public-API half only: a diagonal sheen, a top-left highlight pool, and
—new past what Sapphire's own layer does—an opposite-corner dark pool, added
because the highlight alone read as a flat white wash rather than a curved
surface; real glass darkens away from its light source, not just brightens
toward it. The card's `strokeBorder` became a matching gradient rim instead
of a flat `Color.white.opacity`.

## Consequences

- The notch panel's gesture feel is provably unchanged: its own test suite
  (`NotchGestureInterpreterTests`, exercised through the 3-positional-arg
  call shape `reduce(_:delta:capabilities:)`) still passes unmodified, and
  its `NotchGestureModifier` call site in `NotchRootView` doesn't pass the
  new parameters.
- Any future window wanting its own swipe feel (a different widget, say)
  can pass its own `threshold`/`dominanceMultiplier` through the same two
  parameters rather than another one-off constant.
- The glass surface stays entirely public SwiftUI — safe across macOS
  updates, but caps how close it can get to the exact translucent-sampling
  look `NSGlassEffectView` produces. If a future pass wants that closer
  match, revisit whether the private-API path is worth the fragility then,
  rather than assuming this decision forecloses it permanently.
- Manually confirmed on-device this session: swipe-to-skip triggers on a
  noticeably shorter gesture than the notch panel's own, and the card reads
  as glass rather than a tinted blur.
