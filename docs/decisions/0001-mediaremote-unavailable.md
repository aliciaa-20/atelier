# ADR 0001 — MediaRemote is unavailable, so we use Apple Events

- **Status:** Accepted
- **Date:** 2026-08-31

## Context

Every macOS now-playing app has historically read track data from Apple's private
`MediaRemote.framework`, via `MRMediaRemoteGetNowPlayingInfo`. It is universal: it
reports whatever is playing anywhere on the system, including audio in Safari and
Chrome, and it delivers real-time change events.

In **macOS 15.4** Apple added entitlement verification to the `mediaremoted`
daemon. Clients without an entitlement that only Apple-signed processes hold are
now denied. `MRMediaRemoteGetNowPlayingInfo` returns nil for third-party apps.

This broke boring.notch, Sleeve, `nowplaying-cli`, and most of the ecosystem.
There is an open Feedback request asking Apple for a public replacement API
([FB17228659](https://github.com/feedback-assistant/reports/issues/637)); as of
this writing nothing has shipped.

We are targeting macOS 26.6, well past the cutoff. MediaRemote is simply not an
option.

## Options considered

### 1. Apple Events / AppleScript against individual players — **chosen**

Query Music.app and Spotify directly through their scripting dictionaries.

- Public, documented, stable across releases.
- Full metadata including artwork (Music returns raw image data, Spotify a URL).
- Transport control works too — play/pause, next, previous, seek.
- Costs: covers only apps with a scripting dictionary, so no browser audio. No
  push events, so we poll. Requires the user to grant Automation permission.

### 2. `mediaremote-adapter` (Perl bridge)

[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) loads a
helper framework from `/usr/bin/perl`, a system binary that *is* entitled, and
relays MediaRemote data back out.

- Restores universal coverage and real-time events.
- Costs: depends on an unofficial third-party helper wrapping a private framework
  Apple is actively closing off. Plausibly breaks on any macOS release. A
  significant debugging burden for someone learning Swift.

### 3. `MediaRemoteWizard` (code injection into `mediaremoted`)

Requires disabling System Integrity Protection. Rejected outright — we are not
asking a user to weaken their machine's security for a music widget.

## Decision

Ship option 1 for v1, behind a `NowPlayingSource` protocol with `AppleMusicSource`
and `SpotifySource` conformances.

Keep option 2 on the backlog as an *additional* source. Because sources sit behind
the protocol, adding it later is a new file and a registration, not a rewrite. If
Apple ships a public API, that becomes a third source on the same seam.

## Consequences

- Audio playing in a browser will not appear in the notch. Accepted for v1.
- We poll rather than react. `NowPlayingCoordinator` polls at 1 s when idle and
  0.25 s while the player is expanded, so the scrubber stays smooth without
  burning cycles when nobody is looking.
- We must never scripting-query an app that is not already running, or we would
  launch it. Sources check `NSWorkspace.shared.runningApplications` first.
- The app needs `NSAppleEventsUsageDescription` and a TCC grant, and must degrade
  visibly rather than silently when that grant is denied.
