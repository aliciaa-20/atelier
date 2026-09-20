# Atelier

A Dynamic-Island-style notch app for macOS, named after the MacBook it lives on.

Hover the notch and it expands into a native-feeling now-playing player. While
music plays, a slim pill hugs the notch — battery, volume, and brightness show
there too, briefly, as their own compact widgets. When the track changes (or
you touch a system control), it peeks for a moment and then retracts.

v1 reads from **Spotify**. Apple Music and system-wide playback are on the
backlog, behind the same `NowPlayingSource` seam.

## Status

Phases 0–8 shipped: notch overlay, hover expand/collapse, real Spotify
playback, the full expanded player, the pill/peek/auto-decay state machine,
an extensible Live Activity architecture (Battery, Volume, Brightness),
gesture controls with spring physics, and a system HUD replacement for the
volume/brightness keys.

Also shipped since: a Home/Shelf tab switcher with idle-Home content
(date/time + battery %); a file shelf with drag-and-drop, AirDrop, and
expiry (two known bugs still open — drag-out preview image, Mission
Control triggering on drop); a screen-recording system alert (the first of
several planned); and a lock-screen now-playing widget, rendered via a
private CGS space since macOS has no public lock-screen widget API for
third-party apps (see [ADR 0010](docs/decisions/0010-lock-screen-private-cgs-space.md)).

**Not shipped**: AirPods support is disabled — a crash deep in Apple's own
CoreBluetooth bridge on this machine's current macOS build, not something
fixable from app code. Most of Phase 10's other system alerts (Focus mode,
Wi-Fi/VPN, Bluetooth), the rest of Phase 11 (audio visualizer, synced
lyrics), and Phases 12–16 (productivity widgets, resource monitor, camera
mirror, dev-agent monitoring, settings/launch-at-login) haven't been
started.

114 tests passing.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the phase-by-phase log and
[the design spec](docs/superpowers/specs/2026-08-31-atelier-notch-design.md)
for the original full plan.

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
resolution, AppleScript parsing. AppKit-boundary behavior (window/panel
focus, the media-key event tap, real hardware keys) is manual-verification
only; see `CLAUDE.md`'s Testing section.

## Permissions

Atelier asks for two separate permissions, each with its own reason:

- **Automation** — reads now-playing data via Apple Events to Spotify. If
  you decline, the app tells you so rather than silently showing nothing;
  re-enable it in **System Settings → Privacy & Security → Automation**.
- **Accessibility** — needed to intercept the volume/brightness/mute keys
  and replace the stock macOS HUD. Grant it from the menu-bar item ("Grant
  Accessibility Access…"), shown only while it isn't already granted.

Why Apple Events and not the usual private `MediaRemote` framework? See
[ADR 0001](docs/decisions/0001-mediaremote-unavailable.md).

## License

Private project. All rights reserved.
