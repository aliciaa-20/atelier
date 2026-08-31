# Atelier

A Dynamic-Island-style notch app for macOS, named after the MacBook it lives on.

Hover the notch and it expands into a native-feeling now-playing player. While
music plays, a slim pill hugs the notch. When the track changes, it peeks for a
moment and then retracts.

v1 reads from **Spotify**. Apple Music and system-wide playback are on the
backlog, behind the same `NowPlayingSource` seam.

## Status

Phase 0 — scaffolding. See [the design spec](docs/superpowers/specs/2026-08-31-atelier-notch-design.md)
for the full plan.

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

## Permissions

Atelier reads now-playing data by sending Apple Events to Spotify. On
first launch macOS will ask you to allow this. If you decline, the app tells you
so rather than silently showing nothing — re-enable it in
**System Settings → Privacy & Security → Automation**.

Why Apple Events and not the usual private `MediaRemote` framework? See
[ADR 0001](docs/decisions/0001-mediaremote-unavailable.md).

## License

Private project. All rights reserved.
