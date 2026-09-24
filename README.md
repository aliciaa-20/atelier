# Atelier

**A Dynamic Island for your Mac's notch.**

Atelier turns dead space above your screen into a living surface — a
now-playing player on hover, a slim pill while music plays, and quick
peeks for whatever's happening on your system. Shaped to look like it
belongs there, not bolted on.

## Features

- **Now playing, front and center** — artwork, scrubber, transport
  controls, and a 6-bar waveform that reacts to the *actual audio
  playing*, driven by a real-time CoreAudio tap
- **Drag-and-drop file shelf** — drop a file on the notch, grab it
  later, auto-swept after 24 hours
- **System HUD, reimagined** — volume and brightness replace the stock
  macOS overlay with a matching pill/peek
- **Live system state** — battery, screen recording, and more surface
  through one extensible architecture
- **Lock-screen companion** — the now-playing card follows you past
  the lock screen itself
- **Gesture-driven** — swipe to open, close, or skip tracks, tuned
  with real spring physics
- **Home, Shelf, System Monitor & Calendar tabs** — an idle view for
  when nothing's playing, a week-strip calendar with a funny line for
  each day of the week (scroll through days with a swipe; double-tap to open your calendar app)
- **Weather** — a quiet glance on the idle Home card (tap it for
  conditions, high/low, a quip, and the next five days). Uses Open-Meteo
  and your approximate location, refreshed at most every 30 minutes when
  you open the notch; no background polling
- **Lightweight by design** — animations and pollers run at capped rates
  and idle to nothing when not visible (no continuous redraw for static
  content, no polling when nothing's playing), so a menu-bar accessory
  doesn't act like a background hog

Built on Spotify today, behind a seam designed so any other player is a
drop-in away.

## Status

- **139 tests passing**
- Live phase-by-phase progress: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Full feature survey: [`docs/FEATURES.md`](docs/FEATURES.md)
- Known gap: AirPods support is disabled (a crash in Apple's own
  CoreBluetooth bridge, not fixable from app code)

## Requirements

- macOS 26.0+
- Xcode 26+

## Build & Test

```sh
xcodebuild -scheme Atelier -configuration Debug build
xcodebuild test -scheme Atelier -destination 'platform=macOS'
```

Unit tests cover pure logic — geometry, state transitions, gesture
resolution, parsing, audio normalization. Window/panel focus, hardware
keys, and the audio tap itself are manual-verification only (see
`CLAUDE.md`).

## Permissions

| Permission | Why |
|---|---|
| Automation | Reads now-playing data from Spotify, and jumps Calendar.app to a day, via Apple Events |
| Calendars (full access) | Read-only: shows your week and events in the Calendar tab. Atelier never adds or edits events |
| Location (While Using) | Approximate location, one-shot, to fetch the forecast for the Home weather glance. If denied, weather is simply hidden |
| Accessibility | Intercepts volume/brightness/mute keys for the custom HUD |
| System Audio Recording Only | Powers the live waveform via a system-wide audio tap ([why not per-app](docs/decisions/0012-whole-system-audio-tap.md)) |

**Network:** the only outbound requests are Spotify artwork and the weather
forecast from `api.open-meteo.com` (rounded coordinates only; no account or
key). See [ADR 0015](docs/decisions/0015-weather-open-meteo-corelocation.md).

Decline any of these and Atelier degrades gracefully instead of failing
silently. (Why Apple Events over the private `MediaRemote` framework?
[ADR 0001](docs/decisions/0001-mediaremote-unavailable.md).)
