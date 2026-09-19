# Lock-screen now-playing widget — design

**Status:** approved, not yet implemented.
**Sub-project 1 of N** under the "lock-screen widgets" backlog item
(`docs/ROADMAP.md`'s Backlog section, credited to Alcove/SkyLightWindow in
`CLAUDE.md`). Weather, timer, and any other lock-screen widget are separate
sub-projects, each depending on this one proving the rendering technique
works, each getting its own design/spec/plan pass later.

## Goal

Show Atelier's now-playing info on the lock screen — artwork, title/artist,
a real scrubber, and transport controls — styled as an Atelier card, not
the generic system look. macOS doesn't show a native now-playing widget on
the lock screen on this machine, so this fills a real gap rather than
duplicating one.

This is Atelier's first feature touching a private, undocumented macOS API,
and its first third-party-adjacent code (vendored, not a dependency — see
below).

## Reference apps

Per `check-reference-apps-first`, checked before designing:

- [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) — the
  primary reference. Its `LockScreenPanelManager.swift` is where the actual
  window-level/rendering mechanism came from (see below); its
  `LockScreenMusicPanel.swift` is dramatically larger in scope than what
  this design adopts (parallax, AirPlay device picking, lyrics, fullscreen
  artwork, glass-style customization, panel-width settings — hundreds of
  lines) — deliberately not matched; YAGNI for a personal single-user app.
  Its `extensions/View+Parallax3D.swift` (~40 lines: `onContinuousHover` +
  two `rotation3DEffect`s + a subtle scale) **is** adopted, since it's
  small, self-contained, and a genuine visual feature rather than a setting.
- [Clayton630/QuartzNotch](https://github.com/Clayton630/QuartzNotch) — a
  boring.notch fork taken further; its own `LockScreenPanelManager.swift`/
  `QuartzNotchSkyLightWindow.swift` confirm the same technique (SkyLight
  space delegation) is the standard approach across these apps, not
  something Atoll invented alone.
- [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) — the
  actual rendering mechanism both apps above depend on. MIT-licensed, 211
  stars, actively maintained. Its `SkyLightOperator.swift` (~70 lines) is
  vendored into Atelier directly (see Rendering below), not added as a
  SwiftPM dependency — matches how `NotchShape.swift` and
  `ClickThroughHostingView.swift` were already adapted with credit rather
  than pulled in as packages, and keeps `CLAUDE.md`'s "no third-party
  dependencies" rule literally true. The full package also ships a SwiftUI
  `.moveToSky()` convenience layer and a `TopmostWindowController` this
  design doesn't need — only the `SkyLightOperator` class itself is taken.

## Lock/unlock detection

New `Atelier/LockScreen/LockScreenManager.swift` — observes
`DistributedNotificationCenter.default()` for `com.apple.screenIsLocked`/
`com.apple.screenIsUnlocked` (undocumented notification *names*, but a
long-standing, widely-relied-on mechanism — much lower risk than the
rendering technique below, which is why the two are kept in separate
files). Publishes `@Published private(set) var isLocked: Bool`.

## Rendering — the private-API surface

New `Atelier/System/SkyLightSpaceOperator.swift`, adapted from
`Lakr233/SkyLightWindow`'s `SkyLightOperator.swift` with credit:
`dlopen`s `/System/Library/PrivateFrameworks/SkyLight.framework` and calls
five undocumented `SLS*` C functions to create a CGS "space" at
`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock` (the exact level
Notification Center uses to draw over the lock screen) and move a window
into it (`delegateWindow(_:)`).

**Improvement over the upstream package, not just a copy:** the upstream
`SkyLightOperator.init` force-unwraps every `dlsym` result
(`unsafeBitCast(dlsym(...), ...)` with no nil check) — if Apple ever
renames or removes one of these five symbols in a macOS update, that's an
unconditional crash at app launch, not a graceful degradation. This
vendored version resolves each symbol into an `Optional` function pointer;
if any is `nil`, `SkyLightSpaceOperator.isAvailable` is `false`, logged once
via `Logger`, and `LockScreenPanelController` (below) never attempts to
show the panel at all — the rest of Atelier is completely unaffected.

New `Atelier/LockScreen/LockScreenPanelController.swift` — owns a single,
separate `NSWindow` (not `NotchPanel` — different lifecycle, level, and
screen position entirely). Mirrors Atoll's own approach:
- `[.borderless, .nonactivatingPanel]`, `isOpaque = false`,
  `backgroundColor = .clear`, `hasShadow = false`.
- `level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))` — the
  public, documented API for the screen-shield level — set in addition to
  the SkyLight space delegation, matching Atoll's own belt-and-suspenders
  approach.
- Created lazily on first show, reused afterward (never destroyed/recreated
  per lock cycle); `SkyLightSpaceOperator.shared.delegateWindow(_:)` called
  exactly once, the first time the window is created.
- Shown (`orderFrontRegardless()`) only when **both**
  `lockScreenManager.isLocked` and `nowPlayingCoordinator.current != nil`
  are true; hidden (`orderOut(nil)`) otherwise. Matches the existing
  ambient-content philosophy (Battery's pill only shows when there's
  something worth saying) — no lock-screen card when nothing's playing.
- Positioned bottom-center of the screen (`NSScreen.notchedOrMain`, reusing
  the existing screen-selection helper), clear of the password/Touch ID
  entry area, which sits center-screen.

## Content

New `Atelier/UI/LockScreenMusicCardView.swift` — consumes
`NowPlayingCoordinator` directly (same as `ExpandedPlayerView` does; no new
data source). Two states, local to this view (`@State`, not
`NotchStateMachine` — this window is entirely separate from the notch):

- **Collapsed** (default): artwork (with parallax) + title/artist, small
  footprint.
- **Expanded** (on hover): larger artwork + `ScrubberView` (reused, real
  seek — see below) + play/pause/skip transport, mirroring the notch's own
  pill→expanded pattern without touching `NotchStateMachine`.

**`ScrubberView` reuse requires one small access-control change**: it's
currently `private struct ScrubberView` inside
`Atelier/UI/ExpandedPlayerView.swift`, so it can't be referenced from a
different file. Dropping `private` (making it internal, the module
default) is the only change needed — no move, no duplication, no behavior
change to the notch's own use of it.

New `Atelier/UI/Parallax3DModifier.swift`, adapted from Atoll's
`View+Parallax3D.swift` with credit — same `onContinuousHover` + two
`rotation3DEffect`s + subtle scale-on-hover, applied to the collapsed
card's artwork only.

**Deferred, not built now:** output-device picking (AirPlay/speakers).
`ExpandedPlayerView` already has the `onSelectOutputDevice` closure
wired to `OutputDeviceManager` — a future pass can pass the same closure
into `LockScreenMusicCardView`'s expanded state without any new
architecture, which is why it's safe to skip for this first version.

## Data flow

`NotchController` (already owns `nowPlayingCoordinator`) gains a new
stored property `lockScreenPanelController: LockScreenPanelController`,
constructed in `init()` and handed the *same* `nowPlayingCoordinator`
instance — no second poller, no duplicate Spotify scripting. It also
constructs and owns a `LockScreenManager`, handing it to the panel
controller.

```
LockScreenManager.$isLocked ─┐
                              ├─→ LockScreenPanelController (show/hide + position)
NowPlayingCoordinator.$current ─┘        │
                                          ▼
                              NSHostingView(LockScreenMusicCardView(nowPlaying:))
```

## Error handling

- `SkyLightSpaceOperator` symbol resolution failure (a future macOS
  removing/renaming a private symbol): logged once, feature silently
  disabled, rest of the app unaffected — see Rendering above. This is the
  one concrete failure mode worth naming; there is no other realistic
  failure path (lock/unlock notifications and `NowPlayingCoordinator` are
  both already-proven mechanisms elsewhere in the app).
- No crash-on-launch risk: `SkyLightSpaceOperator`'s symbol resolution runs
  once, lazily, the first time the panel would be shown — not at app
  startup — so even a total resolution failure never affects the rest of
  Atelier's startup path.

## Testing

Fully manual-verification-only — private API behavior, real screen-lock
state, and a real AppKit window can't be meaningfully unit tested, same
treatment as `System/*.swift` and `NowPlayingSource`'s AppleScript pieces
per `CLAUDE.md`'s Testing section. Say so plainly in `docs/ROADMAP.md`
rather than claiming coverage that doesn't exist. Manual checks needed:
lock the screen with music playing → card appears bottom-center; hover →
expands with working scrubber/transport; unlock → card disappears; lock
with nothing playing → no card at all; lock/unlock repeatedly → no
duplicate windows, no crash.

## Out of scope (this spec)

- Weather, timer, reminder, or calendar lock-screen widgets — separate
  future sub-projects.
- Output-device picking (see Content above — deferred, not blocked).
- Any settings/customization surface (panel width, glass style, etc.) —
  Atoll's scope, not this app's; a single-user app doesn't need
  configurability for configurability's sake.
- Any change to the notch's own `NotchState`/`NotchStateMachine` — this
  window is entirely independent.
