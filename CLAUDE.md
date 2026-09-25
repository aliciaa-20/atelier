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

## UI/UX polish — use these skills proactively, not just on request

Alicia wants this app to feel genuinely Apple-native (Dynamic Island/
Control Center quality), not just functionally correct — and she's told
me directly that the gaps she cares about (missing VoiceOver labels, no
depth/shadow, no press feedback, missing keyboard shortcuts) are exactly
the kind of thing she doesn't think to ask for by name, so waiting to be
asked misses them. Whenever touching any SwiftUI view under `Atelier/UI/`
(new or being tuned):

- Run the **`ui-review-tahoe`** skill proactively — not just when asked —
  after any round of visual/sizing changes, to catch accessibility
  (VoiceOver labels, focus/keyboard), depth/shadow, press/hover feedback,
  and animation-quality gaps before she has to spot them in a screenshot.
- Use the **`apple-design`** skill when making layout/spacing/typography/
  motion decisions from scratch (e.g. "make this feel more iOS-like"),
  instead of guessing pixel values purely by trial-and-error round-trips.
- Both are cheap relative to another round of "you like this now?" —
  prefer surfacing a batch of findings in one pass over reacting to one
  screenshot at a time.

### Lessons from the 2026-09-24 screenshot review

- Ask for on-device screenshots of **every tab** after visual work; the biggest
  bug found (memory ring stuck at 99% red) was invisible to code review and tests.
- Verify any system metric against the OS's own tool (`memory_pressure`,
  Activity Monitor) before shipping, and never attach an alarming label
  ("Overloaded") to a number that hasn't been sanity-checked. See ADR 0017.
- Use locale-aware format styles (`.dateTime`) and `TimelineView(.everyMinute)`,
  not hard-coded `dateFormat` strings or `.periodic(from: .now, by: 60)`.
- Icon-only controls get `.help()` tooltips; anything bouncy or parallax honors
  Reduce Motion (`NotchAnimations` reads it live).
- Empty states share one style: soft card, one SF Symbol, one short line.

## Performance — lightweight by design, proactively

Alicia has told me directly this is a differentiator, not a nice-to-have:
Atelier should be lightweight on battery/memory/CPU unlike other menu-bar
accessories, and that should be defaulted to while building, not fixed
after the fact once it's a visible problem. When adding or touching
anything animated, polled, or otherwise continuously running:

- Default to the cheapest mechanism that still reads as smooth. Prefer a
  capped/periodic schedule (`TimelineView(.periodic(from:by:))` at a
  sensible fps) over one that follows the display's full refresh rate
  (`.animation`), and skip the ticking code path entirely when nothing is
  actually animating rather than merely pausing it. `MarqueeText.swift` is
  the reference example.
- Default pollers/timers/taps (`NowPlayingCoordinator`'s poll interval,
  `AudioTap`, any future `LiveActivitySource`) to idle/off when their
  output isn't currently visible or needed — matching the existing pattern
  where `AudioTap`'s lifetime is already tied to `isPlaying`.
- Surface a real memory/CPU/battery tradeoff explicitly when one exists,
  rather than silently picking the expensive option.

## Architecture

Four layers with deliberate seams. The two pure ones carry the test suite.

| Layer | Files | Notes |
|---|---|---|
| App shell | `AtelierApp.swift` | `LSUIElement`, no Dock icon, `NSStatusItem` menu |
| Window | `Notch/NotchPanel.swift`, `Notch/NotchController.swift` | borderless `NSPanel` over the notch |
| Pure logic | `Notch/NotchGeometry.swift`, `Notch/NotchState.swift`, `Notch/NotchPage.swift`, `Notch/CameraHoldOpen.swift`, `Notch/TabOrder.swift` | **unit tested**, no AppKit imports |
| UI | `UI/*.swift` | SwiftUI, driven by `NotchState` |
| Data | `NowPlaying/*.swift` | `NowPlayingSource` protocol + per-app implementations |
| System | `System/*.swift` | `MediaKeyInterceptor` (`CGEventTap`), `AccessibilityPermission`, `CalendarPermission`, `CalendarAppLauncher` (AppleScript into Calendar.app) — manual-verification only, like `NowPlayingSource`'s AppleScript pieces |
| Widgets | `Widgets/*/*.swift` | `LiveActivitySource` conformers (Battery, Volume, Brightness, AirPods, ScreenRecording, ColorPicker) plus non-`LiveActivitySource` tab data sources (`Calendar/CalendarSource` — read-only EventKit, `CalendarMath` is pure and testable; `Weather/WeatherSource` — CoreLocation + Open-Meteo, cached 30 min, no poll loop, `WeatherModel` is pure and unit-tested; `Camera/CameraMirrorSource` — `AVCaptureSession` + preview layer, runs only while the mirror is live and tapped on, `System/CameraPermission` is its TCC helper) — one folder per widget, manual-verification only like `System/*.swift` (except `ColorPicker`'s hex-formatting math, which is pure and unit-tested) |
| Settings | `Settings/*.swift`, `Settings/Panes/*.swift`, `System/LaunchAtLogin.swift` | `SettingsWindowController` (own `NSWindow`, activation-policy flip, ADR 0018) + SwiftUI sidebar panes (General, Appearance, Tabs, Widgets, Teleprompter, Permissions). Manual-verification only; `TabOrder` (pure, in `Notch/`) is the tested part |
| Teleprompter | `Notch/Teleprompter{Script,Scroll,Lines,HoldOpen}.swift` (pure, **unit tested**, Foundation only), `Teleprompter/*.swift`, `UI/Teleprompter*.swift`, `Settings/Panes/TeleprompterPane.swift` | A notch tab (ADR 0019). `TeleprompterScroll` is time-anchored (position = f(start date, WPM)), so nothing ticks; `TeleprompterLineWrapper` (CoreText) + `TeleprompterModel` + views, `ScriptImporter`/`ScriptStore` (tested against real temp files/dirs), `GlobalHotkeys` (Carbon), Ghost Mode = `panel.sharingType` in `NotchController.applyLiveSettings`. Model/wrapper/importer/store are tested; views, hotkeys and Ghost Mode are manual-verification only |
| Shelf | `Shelf/*.swift` | `ShelfItem` (pure, unit-tested) + `ShelfStore` (file I/O, JSON manifest, lazy expiry sweep — unit-tested against real temp directories, not mocked) |
| Lock screen | `LockScreen/LockScreenManager.swift`, `LockScreen/LockScreenPanelController.swift`, `System/SkyLightSpaceOperator.swift` | An entirely separate `NSWindow`/lifecycle from `NotchPanel` — macOS hides ordinary user-session windows on lock, so this delegates into a private CGS space (`SkyLightSpaceOperator`, vendored/hardened from Lakr233/SkyLightWindow) instead. Manual-verification only, like `System/*.swift` |

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
8. **Gesture-resolution logic stays AppKit-free, mirroring Invariant 1.**
   `NotchGestureInterpreter` (threshold crossing, direction-dominance lock,
   momentum discarding, capability gating) imports nothing but Foundation —
   no `NSEvent`. Raw `NSEvent.Phase`/`momentumPhase` is translated into the
   interpreter's own `NotchGesturePhase` vocabulary by the AppKit-side
   `NotchGestureModifier` before crossing the boundary. If you need AppKit
   in the interpreter, the boundary is wrong.

## Reference existing notch apps

There are several real, shipped, open-source macOS notch apps worth checking
before inventing something from scratch — they've already solved problems
we'll hit (notch shape/geometry, hover/expand mechanics, now-playing
integration, menu bar quirks). When stuck on "how does this kind of app
usually do X," look at their actual source before hand-deriving it:

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) —
  where `Atelier/UI/NotchShape.swift` came from. Also has now-playing UI,
  media controls, and file-shelf-style drag & drop (relevant to the backlog).
  Its `NotchHomeView.swift` (`MusicPlayerView`/`MusicControlsView`) is where
  Phase 4's expanded-player layout (artwork left, title/artist/scrubber/
  transport stacked right) came from.
- [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — the
  original source boring.notch itself credits for the notch shape algorithm.
- [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) (formerly
  DynamicIsland) — a more elaborate notch app; also uses the
  `mediaremote-adapter` bridge (relevant to the backlog item of the same
  name). Its `DynamicIslandWindow`/`FirstMouseHostingView` pair is where
  Phase 4's fix for unresponsive buttons in a non-activating panel came
  from — see `docs/decisions/0003-notch-panel-can-become-key.md`.
- Others worth a look if relevant: NotchNook,
  [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop),
  [jackson-storm/dynamicnotch](https://github.com/jackson-storm/dynamicnotch),
  [omerates760/AgentPulse](https://github.com/omerates760/AgentPulse),
  [fr0sty1122/notchify](https://github.com/fr0sty1122/notchify) (media
  controls, browser audio detection, file shelf),
  [navtoj/NotchBar](https://github.com/navtoj/NotchBar) (notch-as-menu-bar
  mechanics), [monuk7735/mew-notch](https://github.com/monuk7735/mew-notch)
  (alternative geometry/hover implementation),
  [Clayton630/QuartzNotch](https://github.com/Clayton630/QuartzNotch) (a
  boring.notch fork taken further),
  [coaxel2/NotchIA](https://github.com/coaxel2/NotchIA) (media player +
  shelf + focus + clipboard, on-device Apple Intelligence), and
  [cshariq/Sapphire](https://github.com/cshariq/Sapphire) (another elaborate
  notch app — worth checking for system-monitor/widget/live-activity
  patterns given the in-progress CPU/mem monitor and widget work).

Further sources for specific future features (backlog items, not v1),
credited via [Ebullioscopic/Atoll's own README](https://github.com/Ebullioscopic/Atoll/blob/dev/ReadMe.md#acknowledgments):
- [**Alcove**](https://tryalcove.com) — Minimalistic Mode interface design
  and the conceptual framework for lock-screen widget integration.
- [**Stats**](https://github.com/exelban/stats) — CPU temperature
  monitoring via SMC access, frequency sampling through IOReport bindings,
  per-core CPU utilisation tracking; relevant to Phase 13's system
  resource monitor.
- [**Open-Meteo**](https://open-meteo.com) — weather API, for a
  lock-screen weather widget.
- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) —
  window-rendering technique for lock-screen widgets.
- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) — C++ source
  for a live music visualizer.
- **Wick** — iOS-like Timer design, for a lock-screen timer widget (no
  repo link in Atoll's own README either, just credited by first name).
- [**OpenUsage**](https://github.com/robinebers/openusage) — LLM usage
  tracking.
- [**OpenRouter**](https://openrouter.ai) — API for automated model
  pricing.

Additional sources found directly (not via Atoll's acknowledgments), for
specific backlog items:
- [**CueNotch**](https://cuenotch.com) — primary reference for Phase 17's
  teleprompter/Ghost Mode; commercial, credited for the product idea only.
- [**jpomykala/NotchPrompter**](https://github.com/jpomykala/NotchPrompter) —
  open-source; its `PrompterWindow.swift` is where the Ghost Mode mechanism
  (`NSWindow.sharingType = .none`) was confirmed for Phase 17.
- [**Avocado**](https://avocadonotch.com) — commercial teleprompter app;
  confirms voice-synced scrolling as real on-device speech recognition
  (not just a mic-level meter) and is the source of the Focus Guide idea
  (dim read lines, highlight current) in Phase 17's scope.
- [**Aboudjem/Sleepless**](https://github.com/Aboudjem/Sleepless) —
  open-source, MIT; the reference for the "keep awake with lid closed"
  backlog idea. Uses `sudo pmset -a disablesleep 1` (undocumented but
  real) via a narrowly-scoped, one-time-authorized passwordless sudoers
  grant — see the feature's own backlog entry in `FEATURES.md` for the
  safety tradeoffs before building anything from this.

This list is also kept in the `check-reference-apps-first` skill
(`.claude/skills/check-reference-apps-first/SKILL.md`) — update both if you
add a repo.

Use `gh api repos/<owner>/<repo>/...` to pull real source directly (as done for
`NotchShape.swift`) rather than guessing at how a technique works from a
screenshot or from memory. Adapt with credit in a comment; don't copy
wholesale without attribution.

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
