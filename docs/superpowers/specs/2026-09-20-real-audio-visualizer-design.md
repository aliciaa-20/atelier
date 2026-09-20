# Real-time audio visualizer — design (v2)

**Status:** approved for implementation planning
**Supersedes:** `2026-09-09-real-audio-visualizer-design.md` (written in the
`worktree-live-activity-architecture` worktree, never merged to main — that
worktree also predates the Shelf and lock-screen layers, so its own
architecture references are stale; this doc stands alone).

## Problem

`WaveformView` (`Atelier/UI/WaveformView.swift`) is fake: its bars animate on
`CGFloat.random(in:)`, driven only by `isPlaying`. The file's own comment
records that a real CoreAudio Process Tap was tried once before and
abandoned as "unreliable in practice," with no surviving code or ADR. v1
calls for a genuinely audio-reactive visualizer instead.

## What changed since the v1 spec

The 2026-09-09 spec proposed a **per-process tap on Spotify specifically**
(`CATapDescription(stereoMixdownOfProcesses: [spotifyPID])`), ported from
Ebullioscopic/Atoll. Atoll's own source documents that this exact mechanism
disturbs the system AVRCP session and breaks the AirPods pause/skip gesture,
so that spec's mitigation was to detect a Bluetooth output route and skip
the tap entirely, falling back to the fake animation.

Since AirPods/Bluetooth is the primary listening setup on this machine, that
fallback would mean the visualizer is fake almost all the time — not an
acceptable v1 outcome. Before committing to that tradeoff, a throwaway spike
tested the alternative Atoll doesn't use: a **whole-system tap**
(`CATapDescription(stereoGlobalTapButExcludeProcesses: [])`, i.e. no
per-process targeting at all) instead of a per-process one.

**Spike result (verified on-device, two independent runs):** the global tap
captured real, music-reactive audio (RMS visibly tracking playback dynamics)
and, in both runs, AirPods pause/skip kept working throughout. The
AVRCP-breaking behavior Atoll documents is specific to *process-scoped*
tapping, not system-audio tapping in general.

**Consequence:** the Bluetooth-route guard is unnecessary. The visualizer
can run all the time, on any output route.

**Tradeoff accepted:** a global tap captures all system audio, not just
Spotify's. In practice this only matters while something else makes sound
during playback (a notification chime, another app) — the visualizer would
react to that too, for that instant. Given the tap only runs while
`isPlaying` (see Lifecycle below), this window is small and was judged
acceptable rather than adding back per-process complexity for a corner case.

## Architecture

### `AudioTap` (new, `Atelier/System/AudioTap.swift`)

1. Build `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`,
   `isPrivate = true`. No process lookup needed — this taps system output
   directly, so Invariant 2 (never launch Spotify) doesn't even come into
   play here.
2. `AudioHardwareCreateProcessTap` → tap `AudioObjectID`.
3. Read `kAudioTapPropertyUID`.
4. `AudioHardwareCreateAggregateDevice` with that tap UID, `isPrivate: true`
   (hidden from Sound settings).
5. `AudioDeviceCreateIOProcIDWithBlock` + `AudioDeviceStart` on the
   aggregate device. The callback runs on a realtime CoreAudio thread — do
   minimal work there (accumulate/copy samples only, no allocation, no
   Swift bridging into `@MainActor` state directly; hop via a lock-free
   ring buffer or an `AsyncStream` continuation).
6. Teardown is symmetric and idempotent: `AudioDeviceStop` →
   `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` →
   `AudioHardwareDestroyProcessTap`, all guarded on "already torn down."
   `deinit` calls the same teardown path (same `nonisolated(unsafe)`
   pattern as `BatterySource.runLoopSource` for properties touched from a
   non-isolated `deinit`).

No `OutputDeviceManager` Bluetooth-route check is needed — that piece from
the v1 spec is dropped. (`OutputDeviceManager.swift` already exists on main
for unrelated output-device work from Phase 8; this feature does not touch
it.)

### DSP: RMS amplitude, not full FFT

Same as v1: skip frequency-band splitting. Split each callback's sample
buffer into 6 equal chunks (matching `WaveformView.barCount`), compute RMS
per chunk via Accelerate's `vDSP_rmsqv` (system framework, no new
dependency), normalize against a running peak so bar heights don't read as
pinned to max or silent depending on a track's mastering loudness.

### Lifecycle: tied to playback state

`AudioTap.start()`/`.stop()` driven by `NowPlayingCoordinator`'s
`current?.isPlaying`, not the app's whole lifetime — mirrors the existing
"faster polling while expanded" pattern (`NotchController` /
`NowPlayingCoordinator.setExpanded`). The tap only exists while there's
something to visualize.

### `WaveformView` integration

`WaveformView` gains a fallback path: when `AudioTap` reports live
magnitudes (a tap is actually running), bar heights come from those 6 RMS
values instead of `CGFloat.random(in:)`. When the tap isn't running (tap
creation failed, e.g. TCC permission not yet granted, or not playing), it
falls back to exactly today's random animation — the waveform is never
blank, only ever "fake but alive" vs. "real."

### Permission

The first tap creation triggers a macOS system-audio-recording permission
prompt (confirmed during the spike). `AudioTap.start()` must tolerate a
denial gracefully (creation fails → fall back to fake animation, don't
retry every playback start in a way that re-prompts repeatedly) — mirrors
`AccessibilityPermission`'s existing pattern for the media-key interceptor.

## Testing

- RMS-to-normalized-bar-height math: pure function, unit-testable against
  fixture sample buffers (silence → near-zero bars, a full-scale sine
  buffer → near-max bars).
- The actual `AudioHardwareCreateProcessTap`/aggregate-device lifecycle:
  manual-verification only, like every other real hardware/TCC-gated piece
  in `System/`. Verify on-device: visualizer reacts to real audio, permission
  prompt appears once and is handled gracefully on denial, AirPods
  pause/skip gestures keep working throughout a full play session (already
  spiked, but worth reconfirming against the final integrated code path,
  not just the throwaway harness).

## Open questions for the implementation plan

- Exact smoothing factor / attack-decay curve for the normalized bar
  heights (the throwaway spike didn't smooth at all — raw RMS per callback
  — so this still needs tuning on-device; try a fixed factor like 0.4
  toward target level per tick as a starting point).
- Whether the pill-state mini waveform (`PillPlayerView`, if it renders its
  own `WaveformView` instance) should also switch to real data, or stay on
  the fake animation for simplicity — leave as an implementation-plan /
  on-device tuning question, not a decision this spec needs to make
  upfront.
- Ring buffer / hand-off mechanism from the realtime IOProc thread to
  `@MainActor` SwiftUI state — needs a concrete choice (e.g. `AsyncStream`
  with a continuation, or a lock-free ring buffer read on a timer) in the
  implementation plan; this spec fixes the *what* (RMS per chunk) not the
  *threading mechanics*.
