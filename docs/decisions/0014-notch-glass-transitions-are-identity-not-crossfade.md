# ADR 0014 — notch Liquid Glass: transitions are `.identity`, not crossfade

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Adding a Liquid Glass background (`.glassEffect(.regular)`) to `NotchRootView`
for `.expanded`/`.peeking`/`.shelf` (flat black stays for `.collapsed`/`.pill`,
per Invariant 7 and the pill's own too-thin-for-glass reasoning) meant deciding
how to animate the swap between glass and flat black, and between one state's
content and another's, on hover-close. Two real bugs were hit and fixed this
session, both from the same underlying cause, before landing on the current
approach.

## Bug 1 — crossfading the glass material while it resizes

First attempt: `.transition(.opacity)` on both the glass and flat-black
branches, so closing would cross-dissolve between them under
`NotchAnimations.close`. Confirmed on-device via frame-by-frame video: the
`.glassEffect()`'s own defining shape (`NotchShape` with `cornerRadii`) was
*also* resizing across the same close animation — expanded's large corner
radii shrinking to pill's small ones — at the exact same time its opacity was
fading. The live system material doesn't render cleanly while its own bounds
are actively morphing mid-fade; it showed as a solid, wrongly-sized rectangle
bleeding through for a few frames.

**Fix:** `.transition(.identity)` on the background branches instead — the
glass/black swap snaps instantly rather than cross-dissolving. The shape
still animates smoothly (that's `cornerRadii`'s own `animatableData`,
unaffected), only the material-vs-flat-color *choice* stops crossfading.

A second attempt tried keeping a constant black fill permanently mounted
*underneath* the glass, with the glass's own opacity fading in/out on top —
avoiding the transition-removal path entirely. This introduced a different,
worse bug: an opaque layer sitting directly behind `.glassEffect()` in the
same view tree gets lensed by the glass *instead of* the real desktop behind
the window, defeating translucency entirely (confirmed on-device: the
"glass" just looked like a foggy dark blob in every state, not only during
transitions). Reverted; `.identity` is the one that shipped.

## Bug 2 — content escaping the outer clip during removal

Content (title/artwork/pill text) was still using `.transition(.opacity)` to
fade during removal (an `if/else` swap between `.expanded`'s view and
`.pill`'s). Confirmed on-device via frame-by-frame video, **twice**, on
opposite edges of the panel: while the exiting view faded, it rendered
*outside* the ancestor `.clipShape(NotchShape(...))`'s current (already-
shrunk) bounds — old, unclipped content briefly visible past where the small
pill had already formed.

Two fixes were tried and failed before finding the real one:

1. Giving content a much faster, dedicated fade (`.transition(.opacity
   .animation(.easeOut(duration: 0.15)))`, distinct from the frame's slower
   spring) — reduced the window but didn't close it; still reproduced.
2. Wrapping the content `if/else` chain in its own extra `.clipShape`,
   redundant with the outer one — also didn't fix it. An exiting
   `.transition`'d subtree in this SwiftUI version renders through a path
   that doesn't reliably respect ancestor clipping *at all* during removal,
   regardless of how fast the fade or how many clips wrap it.

**Fix:** `.transition(.identity)` on content too, matching the background —
content snaps instead of fading. This is also the same lesson already
documented in `LockScreenMusicCardView`'s own type doc (ADR-adjacent, not a
separate ADR): "one persistent view hierarchy, not swapped subtrees." A view
that's genuinely removed and reinserted (an `if/else` branch swap) is not
guaranteed to be clipped correctly by an ancestor whose own shape is
simultaneously animating; a view that's never removed, only faded via a
plain property, stays on the ordinary per-frame render path and is clipped
correctly every time.

## Consequences

- **General rule for this codebase:** don't crossfade (`.transition(.opacity)`
  or similar) a view whose ancestor `.clipShape`/`.frame` is *also* animating
  across the same state change, whether that view is `.glassEffect()` or
  plain content. Use `.transition(.identity)` (snap) instead, or restructure
  to a single persistent view with a continuously-modulated scalar property
  (opacity, scale) rather than an `if/else` subtree swap — see
  `NotchRootView`'s `closeFadeOpacity`/`closeScale` for the latter pattern,
  applied to the *whole* already-composited panel as one unit specifically
  to sidestep this class of bug while still getting a fade-like feel.
- `AtelierSettings.glassIntensity` (the menu-bar transparency slider) is
  implemented as a plain, continuous `.opacity()` on the glass layer — not a
  tint, not tied to any transition — for the same reason: a steady render-time
  property can't hit either bug above, since nothing is resizing or being
  removed while the slider moves.
- A left-edge visual glitch on close specifically when nothing is playing
  (closing to `.collapsed` rather than `.pill`) was still reported after
  adding an explicit `.collapsed` fallback branch (so removal always lands on
  *something* rather than zero matched branches). Left unresolved and
  documented in `NotchRootView.swift` and `docs/ROADMAP.md`'s Phase 18 entry
  rather than guessed at a third time — the previous two fixes in this ADR
  were each found by frame-by-frame on-device video, not by reasoning about
  the code alone, and that's the evidence needed to close this one out too.
