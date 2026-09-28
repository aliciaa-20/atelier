# ADR 0026 — Bend Effect opens the live SCStream lazily; hybrid over full-snapshot capture

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

Phase 19's initial port (2026-09-28) opened `DesktopCapture`'s
`ScreenCaptureKit` stream as soon as `BendEffectController.connect()` saw
any nonzero fold target, and kept it open (throttled 5fps idle / 60fps
bending) until the lid returned fully to its clear angle. In practice the
lid frequently rests slightly closed without ever visibly folding, so the
stream could sit open, decoding frames nobody sees, for most of a session
-- flagged in `docs/ROADMAP.md`'s backlog as a real, isolated CPU/battery
cost, with a sibling open-source project,
[altic-dev/FluidFold](https://github.com/altic-dev/FluidFold), cited as
prior art for a cheaper approach (one-shot `SCScreenshotManager` snapshots
instead of a standing stream).

Reading FluidFold's `Pipeline/EffectController.swift` and
`Pipeline/ScreenCapturer.swift` showed its approach goes further than
"swap the capture backend": it takes a single snapshot during a
lid-angle "pre-warm zone" and **freezes that image for the entire fold
animation** -- no capture at all while the overlay is visible. That is a
real behavior change from Atelier's current fold, which redraws
`FrameStore`'s latest frame every tick so the desktop content (e.g. a
playing video) stays live throughout the bend.

## Decision

Took the hybrid of the two, not FluidFold's full-snapshot approach:

- **Idle-armed window** (lid past the clear angle, fold not yet visible):
  `DesktopCapture.snapshot()` (`SCScreenshotManager.captureSampleBuffer`,
  no stream) seeds `FrameStore`, refreshed on a 250ms throttle
  (`BendMath.shouldRefreshSnapshot`, unit-tested) for as long as the lid
  stays in this state. No `SCStream` exists here at all.
- **Visible-bend window** (`progress` crosses the `0.0005` threshold
  `tick()` already used for overlay show/hide): `BendEffectController`
  opens the live `SCStream` lazily via a new `beginStreaming(displayID:
  generation:)`, mirroring `connect()`'s own error handling since it now
  runs later, off `connect()`'s call stack. The stream stays open with
  the existing hysteresis (full teardown only once `target == 0 &&
  progress <= 0.0005`, unchanged from Phase 19) rather than closing and
  reopening on every threshold crossing, to avoid the restart-latency
  risk FluidFold's own source comments flag ("~0.8s capture-session
  wind-down").
- Rejected full-snapshot-frozen-fold: it would cost the live-content-
  during-fold behavior Phase 19 already shipped, for a battery win beyond
  the idle-armed case that user testing didn't call for. If profiling
  later shows the visible-bend window itself is meaningfully expensive,
  that's a separate, explicit decision to revisit -- not bundled into
  this change.
- `DesktopCapture.start()` no longer clears `FrameStore` on entry
  (`acceptOutput(from:clearFrames:)` now takes an explicit flag): the
  live stream now always starts from an already-visible, snapshot-seeded
  frame, so clearing it would blank the overlay for the stream's async
  startup latency. `stop()` still clears, since by the time it's called
  the overlay is already hidden.

## Consequences

- The standing-stream window shrinks from "armed" to "actually visibly
  bending," which is the minority of a typical session's runtime --
  addresses the ROADMAP battery/CPU concern without touching the
  renderer, Metal pipeline, or UI.
- Visible-fold behavior is unchanged: the desktop still updates live
  frame-by-frame while actually folding, matching Phase 19's original
  spec.
- `BendEffectController` gains a second stream-lifecycle entry point
  (`beginStreaming`, called from `tick()`) alongside `connect()`'s
  now-snapshot-only startup; both funnel real capture errors through the
  same `requiresUserAction`/`interrupt`/`disable` paths, so permission
  revocation and hardware errors are handled identically regardless of
  which path triggered them.
- Confirmed on-device (2026-09-29): no flicker at the visible-threshold
  crossing (the snapshot-to-live-frame handoff) during a real lid close.
