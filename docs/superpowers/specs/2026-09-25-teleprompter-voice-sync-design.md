# Teleprompter stage 4: voice sync — design

Status: draft for review. Follows `2026-09-25-teleprompter-design.md` (stages 1-3, merged) and ADR 0019.

## Goal

The teleprompter follows the speaker's voice. Real word tracking with on-device
`SFSpeechRecognizer` streaming, not a loudness stand-in. Success: read a script
aloud and it tracks you, waits when you pause, and never leaves a dead control.

## Decisions (agreed)

- **Entry point:** a voice-sync toggle in Settings (off by default) **plus** a new
  top-bar strip control, so it can be flipped mid-read.
- **Play/pause = listen / stop listening.** Pausing stops the mic and freezes the
  script; play resumes listening.
- **Voice is the only source of position.** The WPM setting becomes the *glide
  speed* toward the spoken position (no jitter from bursty recognition). If the
  speaker stops, the script stops (no clock drift).
- **Approach A:** voice mode lives inside `TeleprompterScroll` (one pure,
  `Equatable` struct), not a separate type.
- **On-device only.** If the locale has no on-device model, fall back to manual
  WPM mode with an inline note (speech is never sent to Apple's servers).
- **Battery rule:** mic + recognizer run only while voice sync is on AND the
  teleprompter is listening/active.
- **Fallback:** denied / unavailable / unsupported locale -> manual WPM pace with
  an inline note. The control is never dead.

## 1. `ScriptMatcher` (pure, Foundation only, unit-tested)

Input: recognised words (streaming, retroactively revised). Output: new cursor
word index + confidence, or nil when not confident.

- Normalise both sides: lowercase, strip punctuation and diacritics.
- Keep a **cursor** (last confirmed word). Search only a **forward window**
  (~30 words) after it, so one misheard word or a repeated phrase far away can't
  teleport the script.
- Match the **tail** (last 3-4 recognised words), not the whole transcript, so
  partial-transcript revisions don't break alignment.
- Fuzzy word equality: exact, or small edit distance for longer words. Short
  words ("a", "the") carry little weight; they alone can't advance the cursor.
- Confidence gate: advance only when enough of the tail matches.
- Never moves backwards; re-reading a line waits until the cursor is passed.
- **Known limit:** skipping >~30 words won't be followed. Re-sync by hand-scroll
  while paused (exists already). A wider re-acquire search is out of scope.

Tests: exact match, misheard word, skipped words, repeated phrase outside the
window, punctuation/case, partial-transcript revision, no backwards movement.

## 2. Voice mode in `TeleprompterScroll` and the model

`TeleprompterScroll` gains `target: Double?` (nil = manual). It stays pure;
`position(at:)` is still a function of time and anchor.

- `setTarget(_:at:)` re-anchors at the current position (no jump) then stores the
  target. Called on each confirmed matcher advance.
- In voice mode `position(at:)` moves from the anchor toward the target at
  `max(wpm, catch-up rate)` and stops on arrival. The catch-up rate scales with
  the gap so a fast reader doesn't watch the script lag; one named constant,
  tuned on-device.
- `isGliding(at:)` = position short of target.
- `setWPM` mid-glide re-anchors; leaving voice mode returns to manual with no
  jump; `seek` cancels the target.

`TeleprompterModel`:
- New `applySpeechPosition(_:)` entry point (from `ScriptMatcher` output).
- In voice mode `isPlaying` means *listening*, not "clock running".
  `wantsNotchOpen` stays true while listening so the notch doesn't retract in
  pauses between sentences.
- `scheduleFinish` in voice mode fires when the glide reaches the last word with
  the cursor at the end, then `settle` stops listening. It never fires while the
  speaker is silent mid-script.
- `setPointerInside` is a **no-op in voice mode** (pointer leaving must not kill
  the mic mid-read). Manual mode unchanged.
- View ticks only while `isGliding` (MarqueeText pattern); a still script costs
  nothing.

Tests: glide reaches target on time; re-target mid-glide doesn't jump; position
never exceeds target or `totalWords`; `setWPM` mid-glide; leaving voice mode;
`seek` cancels target; model finish/hold-open semantics in voice mode. Tests
pass explicit values (`TeleprompterModel(initialWPM:persistsWPM:)`), never
saved settings.

## 3. Speech layer, permissions, pill, settings (manual verification only)

**`Teleprompter/SpeechRecognizer.swift`** (`@MainActor`; `AVAudioEngine` +
`SFSpeechRecognizer`):
- `start()`: streaming request, `requiresOnDeviceRecognition = true`, mic tap.
  Emits `[String]` words to `ScriptMatcher`; confirmed cursor goes to
  `applySpeechPosition`.
- `stop()`: remove tap, end request, stop engine. Runs on pause, tab leave,
  notch retract, finish.
- Recognition tasks have a duration cap: restart the request seamlessly on cap or
  error; the cursor lives in the model so it survives.
- Denied / no recognizer / unsupported locale -> `voiceUnavailableReason`, model
  falls back to manual, UI shows an inline note.
- RMS level for the pill, throttled ~15 fps, only while the pill is visible.

**Permissions:** `System/MicrophonePermission.swift`,
`System/SpeechPermission.swift` (modelled on `CameraPermission`: `status`,
`requestAccess()`, `openSystemSettings()`); two rows in `PermissionsPane`
(incl. Grant All); `NSMicrophoneUsageDescription` +
`NSSpeechRecognitionUsageDescription` in `Info.plist` (leave
`NSAudioCaptureUsageDescription` alone). Requested on first enabling voice sync,
not at launch.

**Pill:** small black shape hanging below the panel, live waveform + mono
"Listening" label (no trailing dots), soft inner corners joining the panel. Max
panel footprint grows ~20pt (`NotchController` maxHeight includes the pill;
Invariant 3) — measure on-device. Waveform ticks ~15 fps only while listening.
VoiceOver label "Listening for your voice"; Reduce Motion -> static indicator.

**Settings / strip:** `AtelierSettings.teleprompterVoiceSync` (default off);
Teleprompter pane toggle with honest copy about mic use and CPU/battery. New
`TeleprompterControl.voice` case (mic icon, `.help()`, size
`NotchLayout.teleprompterControlSize`), added to `TeleprompterControlLayout` and
the reorder list; a saved order lacking the new case gets a default slot (tested
in `TeleprompterControlLayout`).

## Out of scope

Hotkey for voice sync, wide re-acquire search, server recognition fallback,
script library / AI coach / live captions (later Phase 17 slices).

## Manual verification (not covered by CI)

Recognition quality reading a real script, request-cap restart, pill height on
the notch, permission flows (grant/deny/revoke), VoiceOver on the strip control
and pill, Reduce Motion, Activity Monitor CPU ~0% when paused, mic indicator
off when paused.
