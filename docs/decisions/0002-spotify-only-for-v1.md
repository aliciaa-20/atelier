# ADR 0002 — v1 supports Spotify only

- **Status:** Accepted
- **Date:** 2026-08-31
- **Builds on:** [ADR 0001](0001-mediaremote-unavailable.md)

## Context

ADR 0001 settled *how* we read now-playing data: Apple Events, because MediaRemote
is entitlement-gated. It left open *which* players to support, and assumed Apple
Music and Spotify together.

Each player is a separate scripting dictionary with its own property names, its own
units, and its own quirks. Supporting two from the start doubles the surface area of
the first thing we build, at a point where the notch UI itself is still unproven.

## Decision

v1 ships **Spotify only**. `NowPlayingSource` remains the seam; `SpotifySource` is
its only conformance for now.

The protocol earns its place precisely because adding Apple Music later should be a
new file plus a registration — nothing else. If adding the second source requires
changing the coordinator, the UI, or the model, the abstraction was drawn wrong and
that is the signal to redraw it.

## Verified facts

Read from `/Applications/Spotify.app/Contents/Resources/Spotify.sdef` and confirmed
against a live running instance on 2026-08-31:

| | |
|---|---|
| Bundle identifier | `com.spotify.client` |
| `player state` | enum: `stopped`, `playing`, `paused` |
| `player position` | `real`, **seconds**, read/write — so seeking works |
| `duration` (on track) | `integer`, **milliseconds** |
| Track text properties | `name`, `artist`, `album`, `album artist`, `id`, `spotify url` |
| Artwork | `artwork url` (text) *and* `artwork` (raw `image data`) |
| Commands | `playpause`, `play`, `pause`, `next track`, `previous track` |

Sample response:

```
playing || name=You Make Loving Fun - 2004 Remaster || artist=Fleetwood Mac
       || duration=213693 || position=194.891006469727
```

**The two time units differ.** `duration` is milliseconds, `player position` is
floating-point seconds. Mixing them yields a scrubber wrong by a factor of 1000.
`NowPlayingInfo` normalises both to `TimeInterval` in seconds at the parsing
boundary, and there is a test pinning this.

Raw `artwork` image data means album art needs no network request, which is worth
preferring over `artwork url` once we get to rendering.

## Consequences

- Apple Music playback shows nothing in v1. Accepted.
- `scripts/spotify-probe.applescript` is kept in the repo — running it against a
  live Spotify is the fastest way to see exactly what the parser will receive.
