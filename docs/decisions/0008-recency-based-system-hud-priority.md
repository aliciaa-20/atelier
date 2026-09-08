# ADR 0008 — Volume/Brightness priority is recency-based, not fixed

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

Phase 8's design spec gave Volume and Brightness fixed, distinct
priorities in `LiveActivityStack` (`volume = 20`, `brightness = 19`) —
both above now-playing, matching "a real system HUD interrupts anything
on screen immediately." The spec didn't consider what happens when
*both* are momentarily active at once, since it assumed whichever key
was pressed would simply outrank now-playing and show.

On-device testing surfaced the real gap: pressing brightness while
volume's peek was still showing (both transiently active, since each
decays over ~2.5s) did nothing visible — brightness's content was
published, but volume's fixed higher priority (20 > 19) kept it hidden
until volume's own content decayed away. Real macOS doesn't have this
problem: its volume and brightness HUDs are the same on-screen element,
and pressing either key always shows the one just pressed, instantly.

## Investigation

Fixing the priority *values* alone doesn't solve it — any fixed ranking
between the two reproduces the same bug in the other direction (whichever
has the lower fixed priority can never interrupt the higher one). The
real requirement is dynamic: whichever was touched most recently should
outrank the other, symmetrically in both directions.

First attempt: change `LiveActivityStack`'s equal-priority tie-break from
its existing deterministic, insertion-order-independent rule (see
`LiveActivityStackTests.equalPriorityBreaksTieByIDOrdering`, which
explicitly asserts the *same* result regardless of which order two
equal-priority sources were upserted in) to a recency-based one. Rejected
— that test encodes a real, deliberate invariant for the stack's general
behavior (avoiding non-deterministic flicker among arbitrary
equal-priority sources), and weakening it globally to fix a two-source
special case would be the wrong scope for the change.

Second attempt (adopted): keep `LiveActivityStack` itself untouched.
Instead, make `VolumeSource.priority`/`BrightnessSource.priority`
*computed* properties that read from a small shared object
(`SystemHUDOrder`) tracking which of the two was most recently touched —
whichever matches gets `NotchLiveActivityPriority.systemHUDActive` (20),
the other gets `.systemHUDInactive` (19). Since exactly one of the two
can hold the "active" id at a time, this produces a strict, never-tied
ordering between them — `LiveActivityStack`'s own tie-break logic never
even runs for this case.

This alone wasn't sufficient: `LiveActivityCoordinator.handle` only
re-reads a source's `priority` when *that* source's own content changes
(the closure that calls `source.priority` only fires from that source's
own publisher). A source whose priority changed *because the other
source was just touched* kept a stale snapshot in `LiveActivityStack`
until it happened to publish again — confirmed on-device as the specific
asymmetry ("volume → brightness worked, brightness → volume took a
beat": whichever direction happened to also win `LiveActivityStack`'s own
alphabetical id tie-break on the stale snapshot masked the bug in that
one direction only). Fixed by having `LiveActivityCoordinator.handle`
re-upsert every other currently-active source's priority on every event,
not just the firing source's own.

## Decision

- `NotchLiveActivityPriority.volume`/`.brightness` replaced with
  `.systemHUDActive = 20` / `.systemHUDInactive = 19`, shared by both
  sources rather than one constant each.
- New `SystemHUDOrder` (`Atelier/System/SystemHUDOrder.swift`): a small
  shared class tracking `mostRecentID`, injected into both
  `VolumeSource` and `BrightnessSource` by `NotchController`. Each
  source's `priority` becomes a computed property comparing its own `id`
  against `mostRecentID`. `publish()` calls `hudOrder.touch(id)`.
- `LiveActivityCoordinator.handle` now re-upserts every other
  currently-active source's priority (re-read live) on every event, not
  just the firing source's own — needed because a source's priority can
  now change without that source itself publishing.
- `LiveActivityStack`'s own tie-break logic is untouched, and its
  existing test (`equalPriorityBreaksTieByIDOrdering`) still holds for
  the general case.

## Consequences

- Confirmed on-device: pressing volume then brightness (or the reverse)
  always shows whichever was pressed most recently, immediately, in both
  directions.
- `LiveActivityCoordinator.handle` does slightly more work per event now
  (re-upserting every active source, not just the firing one) — negligible
  at this project's scale (at most five sources), but worth remembering if
  a future phase adds many more concurrently-active sources.
- Any future source whose priority needs to depend on shared external
  state, not just its own content, can follow the same pattern: a
  computed `priority` plus ensuring `LiveActivityCoordinator` re-reads it
  when that external state changes.
