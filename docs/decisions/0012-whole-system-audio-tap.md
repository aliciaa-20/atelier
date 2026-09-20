# ADR 0012 — whole-system CoreAudio tap, not a per-process tap on Spotify

- **Status:** Accepted
- **Date:** 2026-09-20

## Context

`WaveformView` shipped with fake, `CGFloat.random(in:)`-driven bars — a real
system-audio tap had been tried once before, in an earlier uncommitted
session, and abandoned as "unreliable in practice" with no surviving code
or ADR. The real-audio-visualizer feature called for a genuine retry.

The first attempt at a v2 design (2026-09-09) ported
Ebullioscopic/Atoll's own `AudioTap.swift` mechanism directly: a
per-process `CATapDescription(stereoMixdownOfProcesses: [spotifyPID])`
targeting Spotify specifically. Atoll's own source carries a comment
documenting that this exact mechanism disturbs the system AVRCP session —
tapping Spotify's audio process makes AirPods' pause/skip gesture find no
target, and macOS falls back to Siri. That spec's mitigation was to detect
a Bluetooth output route and skip the tap entirely on that route, falling
back to the fake animation.

Since AirPods/Bluetooth is the primary listening setup on this machine,
that mitigation meant the visualizer would be fake almost all the time —
not an acceptable outcome. The question was whether the AVRCP-breaking
behavior was inherent to tapping Spotify's audio at all, or specific to
*process-scoped* tapping.

## Investigation

Atoll's own source only ever demonstrates the per-process approach; there
was no existing reference for tapping system-wide audio instead. A
throwaway spike (per `superpowers:brainstorming`'s spike path — code never
kept) built a standalone Swift binary using
`CATapDescription(stereoGlobalTapButExcludeProcesses: [])` — a whole-system
tap, not scoped to any process — into a private aggregate device, and
printed live RMS while music played over AirPods.

Run twice, independently: both times the tap captured real, music-reactive
audio, and AirPods' physical pause/skip gesture kept working throughout.
The AVRCP-breaking behavior Atoll documents is specific to *process-scoped*
tapping, not system-audio tapping in general.

## Decision

`AudioTap` (`Atelier/System/AudioTap.swift`) uses
`CATapDescription(stereoGlobalTapButExcludeProcesses: [])` — a whole-system
tap — instead of a per-process tap on Spotify. No Bluetooth-route guard
exists; the tap runs on any output route. See
`docs/superpowers/specs/2026-09-20-real-audio-visualizer-design.md` for the
full design this enabled.

**Accepted tradeoff:** a whole-system tap captures all audio, not just
Spotify's — a notification chime or another app's sound would briefly
affect the visualizer too. Given the tap only runs while
`nowPlayingCoordinator.current?.isPlaying`, this window is small; adding
back per-process scoping for this corner case was judged not worth
reintroducing the AVRCP risk.

## Consequences

- The visualizer is real-audio-reactive on every output route, including
  the machine's primary AirPods setup — not just wired/built-in.
- `OutputDeviceManager.isDefaultOutputBluetooth()`-style route detection,
  which the per-process design would have needed, was never built.
- **Manual re-check still open** (see the implementation plan's own
  checklist): an explicit hard-denial-of-permission path, and re-confirming
  AirPods pause/skip against this final integrated code path rather than
  only the standalone spike harness.
- A real, separate gotcha surfaced during manual verification, unrelated to
  the tap-scope decision itself: `AudioHardwareCreateProcessTap` returns
  `noErr` even without the "System Audio Recording Only" TCC permission
  granted, and CoreAudio can take several minutes after a *fresh* grant
  before actually delivering data — worth knowing if the waveform ever
  looks frozen again after a permission change. Recorded in
  `docs/ROADMAP.md`'s Phase 11 entry, not treated as a reason to revisit
  this ADR's decision.
