# ADR 0003 — the notch panel can become key

- **Status:** Accepted
- **Date:** 2026-09-02

## Context

Phase 1's `NotchPanel` used `[.borderless, .nonactivatingPanel]` and additionally
overrode `canBecomeKey`/`canBecomeMain` to `false`. The intent was to guarantee the
panel never steals focus from whatever app is frontmost — Atelier has no Dock icon
and should never feel like it "activates."

Phase 4 added real controls (transport buttons, a draggable scrubber) to the
expanded player, and they did not respond to clicks — first click, every click.

## Investigation

Two independent, compounding causes:

1. **`acceptsFirstMouse`.** AppKit's default is `false`: a click on a control in a
   window that isn't key first activates/focuses the window and is consumed doing
   that, rather than reaching the control. Our panel can never become key (see
   below), so every click looked like this "first click" forever.
2. **`canBecomeKey = false` itself.** Independently of (1), refusing key status
   appears to suppress SwiftUI's own gesture/button recognition inside the hosted
   view entirely.

[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)'s `DynamicIslandWindow`
(itself adapted from boring.notch) resolves both: it sets `canBecomeKey`/
`canBecomeMain` to `true`, and hosts its content in a `FirstMouseHostingView`
overriding `acceptsFirstMouse` to `true`. It still doesn't steal focus — that
guarantee comes from `.nonactivatingPanel` (a style mask flag, not key-status) plus
`isFloatingPanel = true` and `hidesOnDeactivate = false`.

## Decision

Match that combination:

- `NotchPanel.canBecomeKey` / `canBecomeMain` → `true`.
- `NotchPanel.isFloatingPanel = true`, `hidesOnDeactivate = false`.
- New `ClickThroughHostingView<Content>: NSHostingView<Content>` overriding
  `acceptsFirstMouse(for:)` to `true`, used as the panel's `contentView`.

`.nonactivatingPanel` was already carrying the actual "don't activate the app"
guarantee; refusing key status was redundant with it and broke click handling as
a side effect.

## Consequences

- Buttons and the scrubber respond on the first click, as verified manually on
  device.
- Manual re-check needed: confirm the notch panel still never appears in Cmd-Tab
  or steals focus from the frontmost app now that it can become key — expected to
  hold, since that guarantee was never `canBecomeKey`'s to begin with, but Phase 1's
  original verification didn't test this combination.
