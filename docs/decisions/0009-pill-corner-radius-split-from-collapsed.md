# ADR 0009 — `.pill`'s corner radius is separate from `.collapsed`'s

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

`NotchRootView.cornerRadii` originally grouped `.collapsed` and `.pill`
under one shared radius pair, `(top: 6, bottom: 14)` — reasonable at the
time, since both states are visually similar (a slim shape hugging the
notch) and nothing had yet asked for them to diverge.

During Phase 8 polish, on-device feedback asked to reduce the pill's
bottom corner radius specifically (14 → 12, then → 11), to read as less
rounded than it did.

## Investigation

Invariant 7 (`CLAUDE.md`) requires `.collapsed` to stay "visually
indistinguishable from the stock notch" — its corner radii aren't a free
styling choice, they're load-bearing for that guarantee. Changing the
shared `(6, 14)` pair to satisfy a pill-only request would have silently
changed the collapsed/stock-notch shape too, breaking that invariant
without any signal that it happened (nothing else in the shared code path
would have caught it — `NotchGeometryTests` covers the notch *rect*
computation, not the corner-radius styling drawn on top of it).

## Decision

Split the `switch` in `NotchRootView.cornerRadii` so `.collapsed` and
`.pill` are separate cases:

```swift
case .collapsed:
    return (top: 6, bottom: 14)   // must stay pixel-matched to the real notch
case .pill:
    return (top: 6, bottom: 11)   // free to diverge
```

Top radius stays `6` for both (matches the stock notch's own sharp
corner in either state — this is also the value the compact
Volume/Brightness peek borrows, per its own on-device alignment fix
during this same session). Only the bottom radius, which has no
stock-notch counterpart to match, is free to move independently.

## Consequences

- The pill can be tuned further (bottom radius, or anything else) without
  needing to re-verify Invariant 7 each time — that's now structurally
  impossible to break via this code path, not just something to remember.
- `.collapsed`'s radii are still only asserted correct by manual on-device
  comparison against the physical notch (no automated visual-regression
  test exists for shape/radius, only for the underlying rect math) — a
  future change to `.collapsed`'s case specifically still needs that same
  manual verification Invariant 7 has always required.
