# Atelier

A Dynamic-Island-style notch app for macOS — named after the MacBook it lives
on. It turns the notch from dead space into a live surface: a now-playing
player on hover, a slim always-on pill while music plays, and quick peeks
for system events, all shaped to look like it belongs there rather than
bolted on.

Personal project, single target machine (MacBook Pro M3, macOS 26.6).

## What it does

**Now playing, front and center.** Hover the notch and it expands into a
native-feeling player: artwork, title/artist, a draggable scrubber, and
transport controls (play/pause, skip, shuffle, output-device picker). A
6-bar waveform reacts to the audio actually playing — not a canned
animation — driven by a real-time CoreAudio tap on system audio. While
you're not hovering, a slim pill hugs the notch showing artwork and that
same live waveform; move away and it retracts, or wait for a track change
and it peeks briefly before settling back down.

**A file shelf, right where you're already dragging things.** Drag a file
toward the notch and it opens into a shelf — drop it there and it's parked
for later, swept away automatically after 24 hours.

**System state shows up where you're looking.** Volume and brightness
changes replace the stock macOS HUD with a matching pill/peek of their own.
Battery state, a screen-recording indicator, and other system Live
Activities surface the same way — a single extensible architecture
(`LiveActivitySource`) drives all of it, so a new kind of alert is a new
conformer, not a rewrite.

**It follows you to the lock screen.** A now-playing card renders over the
lock screen itself (there's no public API for this — see
[ADR 0010](docs/decisions/0010-lock-screen-private-cgs-space.md) for how),
with the same live artwork, scrubber, and transport.

**Gestures, not just hover.** Swipe to open/close or skip tracks, with a
tuned spring-physics feel — opt-in, gated behind a setting.

**A home for what's next.** A tabbed Home/Shelf switcher on the expanded
player, with an idle-state date/time view when nothing's playing.

v1 reads from **Spotify** specifically, behind a `NowPlayingSource` seam
designed so Apple Music (or anything else) is a new conformer, not a
rewrite of the app.

## Status

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the live phase-by-phase log —
what's shipped, what's mid-flight, and what's still open (including a
couple of known bugs). [`docs/FEATURES.md`](docs/FEATURES.md) has the full
feature survey this roadmap draws from, and
[the original design spec](docs/superpowers/specs/2026-08-31-atelier-notch-design.md)
has the full plan this was built against.

120 tests passing.

**Known gap:** AirPods support is disabled — a crash deep in Apple's own
CoreBluetooth bridge on this machine's current macOS build, not something
fixable from app code.

## Requirements

- macOS 26.0+ (only tested on 26.6, MacBook Pro M3)
- Xcode 26+

## Build

```sh
xcodebuild -scheme Atelier -configuration Debug build
```

## Test

```sh
xcodebuild test -scheme Atelier -destination 'platform=macOS'
```

Unit tests cover pure logic only — geometry, state transitions, gesture
resolution, AppleScript parsing, audio-level normalization. AppKit- and
CoreAudio-boundary behavior (window/panel focus, the media-key event tap,
real hardware keys, the actual audio tap) is manual-verification only; see
`CLAUDE.md`'s Testing section.

## Permissions

Atelier asks for a few separate permissions, each for a specific reason:

- **Automation** — reads now-playing data via Apple Events to Spotify. If
  you decline, the app tells you so rather than silently showing nothing;
  re-enable it in **System Settings → Privacy & Security → Automation**.
- **Accessibility** — needed to intercept the volume/brightness/mute keys
  and replace the stock macOS HUD. Grant it from the menu-bar item ("Grant
  Accessibility Access…"), shown only while it isn't already granted.
- **System Audio Recording Only** — needed for the real-time waveform to
  react to actual audio, via a CoreAudio process tap on system output (not
  scoped to any one app — see
  [ADR 0012](docs/decisions/0012-whole-system-audio-tap.md) for why).
  Without it, the waveform falls back to a non-reactive animation instead
  of failing. Grant it in **System Settings → Privacy & Security → System
  Audio Recording Only**. Note: right after granting it for the first time,
  CoreAudio can take a few minutes to actually start delivering audio —
  the waveform staying still isn't necessarily broken.

Why Apple Events and not the usual private `MediaRemote` framework? See
[ADR 0001](docs/decisions/0001-mediaremote-unavailable.md).

## License

Private project. All rights reserved.
