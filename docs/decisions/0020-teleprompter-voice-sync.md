# ADR 0020 — Teleprompter voice sync: voice is the position, WPM is the glide speed

## Context

Stage 4 of Phase 17 makes the teleprompter follow the speaker. References:
CueNotch (a "Listening" pill), Avocado (confirms real on-device word tracking,
not just a mic-level meter) and NotchPrompter (its "voice activation" is mic
loudness only). Spec: `docs/superpowers/specs/2026-09-25-teleprompter-voice-sync-design.md`.

## Decision

1. **Voice is the only source of position in voice mode; WPM becomes the glide
   speed.** Recognition results arrive in bursts, so `TeleprompterScroll` glides
   toward the spoken word at least at the reading speed (and fast enough to
   arrive within 1.5s for big gaps). A silent speaker means a still script:
   nothing drifts on a clock. Rejected: the clock running with speech nudging
   it (two sources of truth that fight each other).
2. **Voice mode lives inside `TeleprompterScroll`** (a `target`), not a second
   type: one pure `Equatable` struct the tests and view already understand.
   `play` is ignored in voice mode, `seek` leaves it (the model re-enters it
   when listening resumes), and "playing" means gliding.
3. **`ScriptMatcher` is forward-only and windowed** (30 words ahead, last 4
   spoken words, short words weigh less, fuzzy match for long words). One
   misheard word or a repeated phrase far away can't teleport the script, and
   it never rewinds. Rejected: a global search (teleport risk). Known limit:
   skipping more than ~30 words isn't followed; hand-scroll while paused
   re-syncs.
4. **On-device only.** `requiresOnDeviceRecognition = true`, and a locale
   without an on-device model falls back to manual pace with a reason instead
   of sending the user's voice to a server. Privacy over locale coverage.
5. **Play/pause = listen / stop listening.** The mic and recognizer run only
   while voice sync is on AND listening, and stop on pause, tab leave, retract
   and finish. The pointer leaving is a no-op in voice mode (it must not kill
   the mic mid-read).
6. **`SpeechWordSource` is the seam.** The model talks to a protocol; tests use
   a fake, so the voice rules are unit-tested with no microphone. The real
   `SpeechRecognizer` is manual-verification only.
7. **Failure is never a dead control.** Denied permission, no recognizer, no
   on-device model, a lost audio device or a dying recognizer all fall back to
   the manual pace, flip the setting back off and keep a reason (mic.slash
   icon + tooltip + VoiceOver hint, note in Settings).
8. **Permissions are requested on first enabling**, not at launch.

## Consequences

- The top bar has a fourth control (`voice`); orders saved before it get it
  appended.
- The panel's maximum footprint grew by the "Listening" pill (20pt) to respect
  Invariant 3.
- `AVAudioEngine.installTap(onBus:bufferSize:format:block:)` is flagged
  deprecated in the macOS 27.0 SDK; it still works, revisit when a replacement
  is settled.
