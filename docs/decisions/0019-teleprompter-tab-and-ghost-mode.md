# ADR 0019 — Teleprompter: a notch tab, time-anchored scroll, Ghost Mode

## Context

Phase 17 adds a teleprompter. References checked first: CueNotch (commercial;
screenshots only: controls in the notch band, text below, "Listening…" pill),
Avocado (WPM units, Focus Guide, real speech tracking), and
jpomykala/NotchPrompter (open source: a separate borderless window,
`sharingType = .none`, 184x150pt, third-party `HotKey` package; its "voice
activation" is only mic loudness, not word tracking).

## Decision

1. **A tab inside the notch panel**, not a separate window: it reuses the
   panel, tab dots and gestures, and Ghost Mode is one property. The page gets
   its own 320x150pt size via a branch in `NotchRootView.frameSize`
   (pages don't have size objects), inside the player's existing footprint.
2. **`TeleprompterScroll` is time-anchored.** Position is a pure function of a
   start date and WPM (`position(at:)`), so the view samples it on a capped
   `TimelineView(.periodic)` and nothing writes state per frame. Pause, speed
   changes and seeks re-anchor, so nothing jumps. The only timer is one sleeping
   task that fires when a playing script ends. No `PaceSource` protocol yet: the
   speech source (stage 4) drives `seek(to:at:)` instead of the clock.
3. **A greedy word wrapper measures, SwiftUI draws one `Text` per line.**
   `TeleprompterLineWrapper` measures candidate lines with the real font and
   yields each line's first word index; only the visible window of lines is
   built. It breaks only between words: a first version used CoreText's
   framesetter, which also breaks inside hyphenated words and URLs and left
   lines wider than the panel with clipped tails (caught in the final review).
   A word wider than the panel gets a line to itself and is clipped.
4. **Hold-open is always on while playing** (no setting, unlike Camera). Pointer
   pause means "pause while the pointer is over the notch, resume on exit, only
   if it was playing on entry"; `wantsNotchOpen` (playing or pointer-paused) is
   what hold-open consults, so the hover-out that triggers the resume can't
   retract the notch. Playback is deliberately not paused on app-resign-active:
   you read while Zoom is frontmost.
5. **Ghost Mode is `panel.sharingType = .none`, applied live** from settings
   (`NotchController.applyLiveSettings`). It hides the *whole* panel, including
   from the user's own screenshots. **Verified 2026-09-25 (Alicia, macOS 27.0 per
   `sw_vers`): the notch is hidden in a Google Meet screen share.** Apple
   changed capture behaviour in macOS 15, which is why this was checked rather
   than assumed. Not yet tested: QuickTime screen recording, `screencapture`,
   Zoom/Teams, OBS; the Settings copy promises "screen sharing and recordings",
   so test those before relying on it for anything sensitive.
6. **Global hotkeys use Carbon `RegisterEventHotKey`**, not the `HotKey`
   package (no dependencies) and not the Accessibility-gated `CGEventTap`
   (Carbon needs no permission). Keys ⌃⌥P, ⌃⌥↑, ⌃⌥↓: not ⌃⌥Space (macOS input
   source switch) and not bare ⌘↑/⌘↓ (they'd break text editing). Opt-in, off
   by default.
7. **Script import** uses `NSAttributedString`'s document importer for
   `.rtf/.doc/.docx` (no dependency); plain text falls back from UTF-8 through
   BOM detection to Windows-1252 then Latin-1 (`usedEncoding` alone only
   detects BOM files).

8. **A manual pause keeps the notch open; only a finished script retracts it.**
   Pausing (e.g. ⌃⌥P) with the pointer outside must not collapse the notch:
   a presenter pausing for a question keeps their place in view.
   `TeleprompterModel.hasFinished` gates the auto-retract.

## Consequences

- Voice sync (stage 4) has its own plan; the "Listening…" pill hanging below the
  panel needs ~20pt beyond 150pt, so the max footprint may grow slightly.
- Ring text (~8pt in a 28pt ring) and the flank controls' fit are settled
  on-device.
- Ghost Mode's privacy claim rests on the Meet result in decision 5 only.
