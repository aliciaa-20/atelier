# Atelier — project context

## What this is

A Dynamic-Island-style notch app for macOS. Hovering the notch expands it into a
now-playing player; a slim pill hugs the notch while music plays; a track change
makes it peek briefly then retract.

Named after the MacBook it runs on. Personal project, private repo, single target
machine: MacBook Pro M3 (Mac15,3), macOS 26.6.

> **Unrelated context warning:** a `CLAUDE.md` for a different project (DevFlow)
> lives at `~/Downloads/CLAUDE.md` and is inherited by directory traversal. It has
> nothing to do with Atelier. Ignore it.

## Who I'm working with

Alicia is new to Swift, macOS development, and Claude Code. This project is
deliberately also a vehicle for learning all three.

- Explain Swift and AppKit/SwiftUI concepts as they come up, briefly, in context.
- Keep steps small and verifiable. Prefer "build it and look at it" checkpoints.
- When a Claude Code mechanic is genuinely the right tool for the step at hand
  (plan mode, a skill, a subagent, a hook, a slash command), name it and say why.
  Don't manufacture excuses to demo features.
- She reviews every diff. Keep them small and legible.

## Architecture

Four layers with deliberate seams. The two pure ones carry the test suite.

| Layer | Files | Notes |
|---|---|---|
| App shell | `AtelierApp.swift` | `LSUIElement`, no Dock icon, `NSStatusItem` menu |
| Window | `Notch/NotchPanel.swift`, `Notch/NotchController.swift` | borderless `NSPanel` over the notch |
| Pure logic | `Notch/NotchGeometry.swift`, `Notch/NotchState.swift` | **unit tested**, no AppKit imports |
| UI | `UI/*.swift` | SwiftUI, driven by `NotchState` |
| Data | `NowPlaying/*.swift` | `NowPlayingSource` protocol + per-app implementations |

**v1 supports Spotify only.** The `NowPlayingSource` protocol still exists and is
still the seam — but only `SpotifySource` conforms to it for now. Apple Music is a
later phase, and adding it must not require changing anything outside a new file
plus one registration. If it does, the protocol is wrong.

### Invariants — do not break these

1. **`NotchGeometry` and `NotchState` import nothing but Foundation/CoreGraphics.**
   They are pure value types. If you need AppKit in there, the boundary is wrong.
2. **Never scripting-query a media app that isn't already running.** Check
   `NSWorkspace.shared.runningApplications` for `com.spotify.client` first, or we
   launch Spotify on the user unprompted.
3. **The panel is always sized to the maximum expanded footprint.** Only the
   SwiftUI content animates. Resizing the window per state causes visible jank.
4. **Non-interactive regions get `.allowsHitTesting(false)`.** Transparent SwiftUI
   views still swallow clicks, and this panel sits over the menu bar.
5. **Spotify time units differ between fields.** `duration` is milliseconds,
   `player position` is floating-point seconds. Normalise both to seconds at the
   parsing boundary. See `docs/decisions/0002-spotify-only-for-v1.md`.
6. **Never use `MediaRemote`.** It is entitlement-gated since macOS 15.4 and
   returns nil. See `docs/decisions/0001-mediaremote-unavailable.md`.
7. **Collapsed state must be visually indistinguishable from the stock notch.**

## Commands

```sh
xcodebuild -scheme Atelier -configuration Debug build     # build
xcodebuild test -scheme Atelier -destination 'platform=macOS'   # unit tests
```

`/build` is a slash command that builds and relaunches the app.

```sh
osascript scripts/spotify-probe.applescript   # see exactly what Spotify returns
```

## Testing

Swift Testing (`import Testing`), not XCTest. Unit tests cover geometry math,
state transitions, and AppleScript output parsing — all pure functions.

Note for Spotify parsing: `duration` comes back in **milliseconds**, while
`player position` is in **seconds** as a float. Getting this wrong yields a
scrubber that is off by 1000x, so it gets an explicit test.

Anything needing a real notch, a real TCC grant, or a running media player is
**manual** and stays out of CI. Say so plainly rather than pretending coverage
exists.

## Conventions

- Swift 6, strict concurrency. SwiftUI first, AppKit where SwiftUI can't reach.
- No third-party dependencies. If one seems necessary, discuss it first.
- Deployment target macOS 26.0.
- Small, focused commits with a clear subject line.
