# ADR 0022 — Apple Music artwork: iTunes Search API fallback for streaming tracks

- **Status:** Accepted
- **Date:** 2026-09-27

## Context

Adding `AppleMusicSource` (alongside `SpotifySource`, arbitrated by
`NowPlayingArbiter`/`MultiNowPlayingSource`), artwork showed for some tracks
and not others. Investigation (comparing a locally-downloaded library track
against a track streamed straight from the Apple Music catalog) found:

- `count of artworks of current track` is `2` for a downloaded (`file
  track`) item, and its `data of artwork 1 of current track` succeeds.
- The same call is `0` for a streaming (`URL track`) item — consistently,
  across multiple tracks/artists — and `data of artwork 1 of current track`
  raises `-50 Parameter error`.

This is a genuine Music.app AppleScript dictionary limitation, not a bug in
`AppleMusicOutputParser`/`AppleScriptRunner`: streaming playback simply
doesn't expose scriptable artwork. Checked boring.notch's own
`AppleMusicController` (reference app) — it hits the same call with the same
try/catch-to-empty fallback and has no workaround, confirming this isn't
something already solved elsewhere. Since most real Apple Music listening is
streaming rather than downloaded, shipping without a fallback would mean
artwork rarely appearing in practice.

## Decision

- When `AppleMusicOutputParser` reports no artwork data, `AppleMusicSource`
  falls back to the public **iTunes Search API**
  (`https://itunes.apple.com/search?term=<artist> <title>&entity=song`) —
  no API key, first result's `artworkUrl100` with `100x100bb` swapped for
  `600x600bb` to get a real resolution.
- `ITunesArtworkResponseParser` (JSON decode + URL upscale) is pure and
  unit-tested with fixture JSON. `ITunesArtworkLookup` (the network call) is
  manual-verification only, like the rest of the AppleScript/network layer.
- **Cached per track, not per poll:** `ITunesArtworkLookup` only fires a
  request when the (title, artist, album) key changes, matching the 1s/250ms
  poll interval otherwise hitting the network on every tick — the same
  "idle to nothing when not needed" principle as `WeatherSource` (ADR 0015).
- Local/downloaded tracks never touch the network at all — the AppleScript
  artwork path is checked first and wins when it succeeds.

## Rejected

- **Accept the limitation, show the placeholder for streaming tracks.**
  Simpler, matches the reference apps, but would mean no artwork for most
  real-world Apple Music usage. Alicia chose the fallback instead.
- **Fetch via MediaRemote.** Forbidden outright — entitlement-gated since
  macOS 15.4 (ADR 0001, invariant 6).

## Consequences

- Atelier now makes an outbound request to `itunes.apple.com` when Apple
  Music is playing a streaming track with no local artwork. Needs a README
  mention alongside the existing Open-Meteo network disclosure.
- No API key to leak/rotate, but a third-party API behavior change
  (response shape, rate limiting) could silently break this fallback —
  it degrades to the placeholder, not a crash, if the request fails or
  returns no results.
- Not yet verified: behavior when the API returns a false-positive match
  (wrong cover art for a same-named track by a different artist/release).
