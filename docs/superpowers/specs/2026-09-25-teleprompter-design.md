# Teleprompter / Ghost Mode (Phase 17) — design

## Goal

A notch teleprompter: a new tab whose script scrolls right under the camera, hidden
from screen shares and recordings (Ghost Mode), and (stage 4) follows the speaker's
voice. Design language follows CueNotch; mechanics borrow from NotchPrompter and Avocado.

## Decisions (agreed with Alicia, 2026-09-25)

- **Approach A:** a tab inside the existing notch panel (`NotchPage.teleprompter`),
  not a separate window. Ghost Mode is `panel.sharingType = .none`.
- **Size:** 320 x 150pt total (NotchPrompter's 150pt), including the notch band.
  Its own `teleprompterSize`, like `shelfSize`/`calendarSize`; the panel stays sized to
  the largest page (Invariant 3). About 118pt is text.
- **Script source:** typed/pasted in a new Settings "Teleprompter" pane, plus drop a
  `.txt`, `.md`, `.doc`, `.docx` or `.rtf` file there. One script in this spec; the
  library (folders + search) is a later slice.
- **Pace:** play/pause + speed in **WPM** (50-300, default 140), not pixels/sec.
  Voice sync is stage 4 and goes **straight to real word tracking**
  (`SFSpeechRecognizer`), not a mic-loudness stand-in.
- **Extras in scope:** Focus Guide (subtle dimming of read lines), top/bottom edge
  fades, pause on hover, global hotkeys (no third-party lib), time readout + ring.
- **Text:** SF Pro bold, left-aligned by default; a Mono option in Settings.

## Reference findings

- **CueNotch** (commercial; screenshots only): controls sit in the notch band flanking
  the camera; text starts below; ~3 lines, bold, edge lines clipped/faded; a separate
  "Listening..." pill with live waveform hangs below the panel; Ghost Mode shown as a
  state. Idea and layout credit only, no source.
- **Avocado:** real on-device speech tracking, Focus Guide, WPM units, cmd+up/down.
- **jpomykala/NotchPrompter** (open source): `sharingType = .none`, hover controls,
  edge fades, 184x150pt window. Its "voice activation" is only mic loudness (RMS), not
  word tracking. It uses the third-party `HotKey` package, which we do not.

## UI

- **Control strip (in the notch band, flanking the camera):** left = play/pause + speed
  chip (steps WPM); right = `TeleprompterRing`, a ~26pt progress ring (starts at 12
  o'clock, round cap, 15% track) with **time remaining** centred; elapsed/total in a
  `.help()` tooltip. A small ghost icon shows while Ghost Mode is on. Exact chip
  shape is settled on-device.
- **Text area:** bold, ~3 lines, edge fades top and bottom, Focus Guide dims lines
  already read. Scroll pauses while hovered. Reduce Motion: the scroll steps line by
  line instead of gliding (`NotchAnimations` reads it live).
- **"Listening..." pill:** hangs below the panel while voice sync is on, with a live
  waveform. Needs ~20pt beyond the 150pt, so the max footprint may grow slightly in
  height; measure before fixing the number.
- Empty script: the shared empty-state card (soft card, one SF Symbol, one line).
- Icon-only controls get `.help()` and VoiceOver labels.

## Components

**Pure (`Notch/` or `Teleprompter/`, Foundation only, unit-tested):**
`TeleprompterScript` (text -> words/lines, word count), `TeleprompterScroll` (fractional
word position, WPM -> position math, progress, current line, time remaining),
`PaceSource` (protocol: manual timer now, speech later), `ScriptMatcher` (stage 4:
forward-only fuzzy alignment of recognised words), `TeleprompterHoldOpen` (keeps the
notch open while reading; modelled on `CameraHoldOpen`).

**Manual-verification only:** `ScriptImporter` (`.txt`/`.md` plain text with light
Markdown stripping; `.doc`/`.docx`/`.rtf` via `NSAttributedString`'s document
importer), `ScriptStore` (one script file in Application Support; later reused by the
library in `ShelfStore`'s JSON-manifest shape), `GlobalHotkeys` (`System/`, Carbon
`RegisterEventHotKey`, registered only while the tab is enabled),
`SpeechPaceSource` + `SpeechPermission` (stage 4), the tab view, `TeleprompterRing`,
the Settings pane, and the `AtelierSettings` flags (WPM, font style, font size, Ghost
Mode, voice sync, hotkeys).

## Data flow

`ScriptStore` -> `TeleprompterScript` -> `TeleprompterScroll` (position). A `PaceSource`
moves the position: the manual source ticks it at the WPM rate; the speech source sets
it from recognised words via `ScriptMatcher`. The view reads the position for the text
offset, ring fraction (position / total) and time remaining.

## Behavior and invariants

- Invariants 1 and 8: pure types import only Foundation/CoreGraphics.
- Invariant 3: the panel stays the max footprint; only SwiftUI content animates.
- Invariant 4: non-interactive regions (fades, pill) get `.allowsHitTesting(false)`.
- **Ghost Mode applies to the whole panel**, not just this tab, so the notch is also
  invisible to the user's own screenshots while on.
- **Performance:** scrolling uses a capped `TimelineView(.periodic)` and only ticks
  while playing (`MarqueeText` is the reference). Mic and speech recognizer run only
  while voice sync is on *and* playing. Hotkeys are idle when the tab is disabled.
  Voice sync is the real battery/CPU cost of this feature; surface it in Settings copy.
- **Permissions:** only stage 4 needs Microphone + Speech Recognition (rows in the
  Permissions pane, TCC helper modelled on `CameraPermission`, usage-description
  strings). Carbon hotkeys need no permission, unlike the Accessibility-gated
  `CGEventTap`.

## Errors

- Empty script: empty-state card.
- Import failure or unsupported type: a message; the current script is untouched.
- Speech denied/unavailable/unsupported locale: fall back to manual pace with an
  inline note.

## Stages

1. Pure logic (`TeleprompterScript`, `TeleprompterScroll`, `PaceSource` manual,
   `TeleprompterHoldOpen`) + `ScriptImporter` + `ScriptStore`, tested.
2. The tab: `NotchPage.teleprompter`, size, control strip, ring, text view, Settings
   pane with editor + file drop, font/WPM settings.
3. Ghost Mode (menu-bar + Settings toggle, ghost icon) verified against a real screen
   recording, plus global hotkeys.
4. Voice sync: `ScriptMatcher`, `SpeechPaceSource`, permissions, Listening pill.
   Built and verified on its own.

## Testing

Unit tests (Swift Testing) cover scroll/WPM math, script splitting, time estimate,
hold-open and `ScriptMatcher`. Everything needing a real notch, a TCC grant, a screen
recording, the microphone or hotkeys is **manual** and stays out of CI; say so plainly
rather than pretending coverage exists.

## Out of scope for this spec

Script library (folders + search), AI rehearsal coach, live meeting captions, Magic
Polish, Memorize Mode, `.pptx` notes import, Director Mode (remote control). All stay
in ROADMAP Phase 17 / FEATURES as later slices.
