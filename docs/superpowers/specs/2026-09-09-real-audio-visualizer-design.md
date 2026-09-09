# Real-time audio visualizer — design

**Status:** approved for implementation planning
**Part of:** Phase 11 (Now-Playing Live Activity + lock-screen widget)

## Problem

`WaveformView` (`Atelier/UI/WaveformView.swift`) is fake: its bars animate on
`CGFloat.random(in:)`, driven only by `isPlaying`, not real audio. This
matches what boring.notch/Atoll/dynamicnotch actually ship too — their own
"equalizer" components do the same thing — so it isn't a regression, but
Phase 11 calls for a genuinely audio-reactive visualizer.

Atelier already tried a real CoreAudio Process Tap for this once, in an
earlier, uncommitted session, and abandoned it as "unreliable in practice"
(the only trace of that attempt is a comment in `WaveformView.swift` — no
ADR, no code, since it was never committed). This spec is an informed
retry: research into Ebullioscopic/Atoll's own `AudioTap.swift` (pulled via
`gh api`, per check-reference-apps-first) surfaced a specific, documented
failure mode that plausibly explains the earlier abandonment.

## The Bluetooth/Spotify conflict (root cause of the earlier failure)

Atoll's `AudioTap.swift` carries this comment verbatim:

> AirPods/Bluetooth output + Spotify don't mix: process-tapping Spotify
> into our private aggregate device disturbs the system Now Playing /
> AVRCP session, so the AirPods pause gesture finds no target and macOS
> falls back to Siri... While a Bluetooth route is active, skip tapping
> Spotify to preserve media control.

Atelier is Spotify-only (v1, [ADR 0002](../../decisions/0002-spotify-only-for-v1.md))
and the primary listening device on this machine is AirPods. A naive
Process Tap on Spotify's audio process is very likely exactly what made
the earlier attempt "unreliable" — it would have intermittently broken
AirPods media controls, which reads as "the whole feature doesn't work"
even though the audio capture itself succeeded.

**This spec's mitigation, ported directly from Atoll:** before creating the
tap, check whether the current default output route is Bluetooth. If it
is, skip the tap entirely for that playback session and fall back to the
existing fake `WaveformView` animation. Re-check on every start (route can
change between songs/plays).

## Architecture

### `AudioTap` (new, `Atelier/System/AudioTap.swift`)

Ports Atoll's mechanism directly:

1. Find Spotify's `AudioObjectID` via `kAudioHardwarePropertyProcessObjectList`
   + `kAudioProcessPropertyBundleID`, matching `com.spotify.client`. Guard:
   only proceed if Spotify is actually running (Invariant 2 still applies
   — this is a read of an already-tapped-in process, not a launch, so the
   invariant isn't at risk, but the object simply won't exist if Spotify
   isn't running).
2. Build a `CATapDescription` for that one process ID, `isMixdown = true`,
   `isMono = true` (matches Atoll; we only need amplitude, not stereo
   imaging).
3. `AudioHardwareCreateProcessTap` → tap `AudioObjectID`.
4. Read `kAudioTapPropertyUID`.
5. `AudioHardwareCreateAggregateDevice` with that tap UID, `isPrivate:
   true` (hidden from Sound settings, matches Atoll).
6. `AudioDeviceCreateIOProcID` + `AudioDeviceStart` on the aggregate
   device. The IOProc callback runs on a realtime CoreAudio thread —
   matches Atoll's own comment, do minimal work there (copy/accumulate
   samples only, no allocation, no Swift bridging).
7. Teardown is symmetric and idempotent: `AudioDeviceStop` →
   `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` →
   `AudioHardwareDestroyProcessTap`, all guarded on "already torn down."
   `deinit` calls the same teardown path (same `nonisolated(unsafe)`
   pattern as `BatterySource.runLoopSource` for the properties touched
   from a non-isolated `deinit`).

### Bluetooth-route guard

New `OutputDeviceManager.isDefaultOutputBluetooth() -> Bool`, reading
`kAudioDevicePropertyTransportType` on `currentDefaultOutputDevice()` and
comparing against `kAudioDeviceTransportTypeBluetooth`. Pure enough at the
comparison level to unit-test against a fixture transport-type value, even
though the actual `AudioObjectGetPropertyData` call stays manual-verification
like the rest of `System/`.

`AudioTap.start()` checks this first and no-ops (does not create a tap)
when `true`.

### DSP: RMS amplitude, not full FFT

Deliberately skip frequency-band splitting (Atoll's C++ `AudioBridge` does
FFT via a custom bridge) — more moving parts, more failure surface, and
`WaveformView`'s 6 bars don't need true per-band data to read as
convincing. Instead: split each callback's sample buffer into 6 equal
chunks, compute RMS per chunk via Accelerate's `vDSP_rmsqv` (system
framework, not a new dependency — consistent with "no third-party
dependencies" from `CLAUDE.md`), normalize against a running peak (so
volume level doesn't just look pinned at max or silent depending on the
track's mastering loudness).

### Lifecycle: tied to playback state

`AudioTap.start()`/`.stop()` driven by `NowPlayingCoordinator`'s
`isPlaying`, not the app's whole lifetime — mirrors the existing "faster
polling while expanded" pattern (`NotchController`'s
`nowPlayingCoordinator?.setExpanded`). Smaller blast radius: the tap only
exists while there's something to visualize, and the Bluetooth-route edge
case only matters during that same shorter window.

### `WaveformView` integration

`WaveformView` gains a fallback path: when `AudioTap` reports live
magnitudes (i.e., a tap is actually running), bar heights come from those
6 RMS values instead of `CGFloat.random(in:)`. When the tap isn't running
(Bluetooth route active, tap creation failed, Spotify not running, or not
playing), it falls back to exactly today's random animation — so the
waveform is never blank, only ever "fake but alive" vs. "real."

## Testing

- `OutputDeviceManager`'s Bluetooth-transport-type comparison: pure enough
  to unit test against a fixture `AudioDeviceTransportType` value.
- RMS-to-normalized-bar-height math: pure function, unit-testable against
  fixture sample buffers (silence → near-zero bars, a full-scale sine
  buffer → near-max bars).
- The actual `AudioHardwareCreateProcessTap`/aggregate-device lifecycle:
  manual-verification only, like every other real hardware/TCC-gated piece
  in `System/` and `NowPlayingSource`'s AppleScript side. Verify on-device:
  visualizer reacts to real audio on wired/built-in output, falls back to
  the fake animation on Bluetooth output, and — the actual regression this
  guards against — AirPods pause/skip gestures keep working throughout a
  full play session on Bluetooth output.

## Open questions for the implementation plan

- Exact smoothing factor / attack-decay curve for the normalized bar
  heights (Atoll uses a fixed `0.4` factor toward target level each
  60fps tick — worth trying that as a starting point before tuning
  on-device).
- Whether the existing pill-state mini waveform (`PillPlayerView`) should
  also switch to real data, or stay on the fake animation for simplicity
  (it's small enough that the difference may not be visible) — leave as a
  question for the implementation plan / on-device tuning pass, not a
  decision this spec needs to make upfront.
