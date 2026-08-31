# Atelier — a macOS notch app

## Context

Alicia wants to build a Dynamic-Island-style notch app for her MacBook Pro M3 14"
(hostname *Atelier*), and to use the project as a vehicle for learning Claude Code
by doing. She is a **complete Swift/macOS beginner**, so the plan is structured as
phases that each ship something visible *and* each introduce one Claude Code
mechanic deliberately.

**v1 goal:** hovering the notch expands it into a native-feeling now-playing
player (artwork, title/artist, scrubber, transport controls); while music plays a
slim pill hugs the notch; a track change makes it auto-peek for a couple of
seconds then retract.

**Non-goals for v1:** file shelf, system HUD replacement, App Store distribution,
notarization, multi-monitor polish.

### Environment (verified)

| | |
|---|---|
| Machine | MacBook Pro M3, Mac15,3 — has a notch, 8 GB RAM |
| OS | macOS 26.6.2 (build 25G83) |
| Xcode | 26.6 (17F113) — **license not yet accepted** |
| GitHub | `gh` authed as `aliciaa-20`, scopes `gist, read:org, repo` |
| Working dir | `~/Downloads/dev-macos` — empty except `.remember/` |

### The one hard constraint, verified before planning

Apple's private `MediaRemote` framework — how every notch app used to read
now-playing data — **stopped working for third-party apps in macOS 15.4**.
`mediaremoted` now checks for an entitlement only Apple-signed processes hold, so
`MRMediaRemoteGetNowPlayingInfo` returns nil. This broke boring.notch, Sleeve, and
`nowplaying-cli`. Apple has an open Feedback request for a public replacement
([FB17228659](https://github.com/feedback-assistant/reports/issues/637)); nothing
has shipped.

**Decision:** v1 reads now-playing over **AppleScript** (Apple Music + Spotify),
behind a `NowPlayingSource` protocol. The
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) Perl bridge —
which gets universal coverage including browsers, at the cost of a third-party
helper that can break on any macOS release — becomes an optional second source in
a later phase. Record this as ADR 0001 so the reasoning survives.

---

## Architecture

Four layers, each testable on its own.

```
NSStatusItem (menu bar: Settings, Quit)
        │
NotchController ──owns── NotchPanel (borderless NSPanel over the notch)
        │                      │
        │                      └── NotchRootView (SwiftUI)
        │                            ├── CollapsedPillView
        │                            └── ExpandedPlayerView
        │
        ├── NotchGeometry      (pure: screen → notch rect)        ← unit tested
        ├── NotchState         (pure: state machine)              ← unit tested
        │
        └── NowPlayingCoordinator
              └── [NowPlayingSource]
                    ├── AppleMusicSource ─┐
                    ├── SpotifySource ────┼── AppleScriptRunner   ← parsing tested
                    └── (later) MediaRemoteAdapterSource
```

### Window layer

`NotchPanel: NSPanel` with `[.borderless, .nonactivatingPanel]`,
`level = .statusBar`, `isOpaque = false`, clear background, no shadow,
`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.

Key technique: **the panel is always sized to the maximum expanded footprint** and
anchored top-centre; only the SwiftUI content animates inside it. This avoids
window-resize jank entirely. Regions that should not swallow menu-bar clicks get
`.allowsHitTesting(false)` — transparent SwiftUI views still capture events
otherwise. (Fallback if hit-testing proves fiddly: animate the panel frame with
`NSAnimationContext`.)

Geometry comes from `NSScreen`: pick the built-in display via
`safeAreaInsets.top > 0`; notch height is `safeAreaInsets.top`; notch width is
`frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`. Pure
function, hard-coded fallback for notchless/external displays.

### State machine

```swift
enum NotchState: Equatable {
    case collapsed              // stock-looking notch
    case pill                   // slim always-on sliver, music playing
    case peeking(until: Date)   // auto-shown on track change, ~2.5s
    case expanded               // full player, hover
}
```

Transitions: hover-in → `expanded`; hover-out → `pill`/`collapsed` after a short
grace delay; track change → `peeking` → decays back unless hovered. A pure value
type with a `reduce(event:) -> NotchState` — no AppKit, fully unit-testable, and a
perfect first target for the TDD skill.

### Now-playing layer

```swift
struct NowPlayingInfo: Equatable {
    let title, artist, album: String
    let artwork: ArtworkRef?      // .data(Data) for Music, .url(URL) for Spotify
    let isPlaying: Bool
    let duration, elapsed: TimeInterval
    let sourceBundleID: String
}

protocol NowPlayingSource {
    var isAvailable: Bool { get }              // is the app actually running?
    func fetch() async -> NowPlayingInfo?
    func playPause() async
    func next() async
    func previous() async
    func seek(to: TimeInterval) async
}
```

`AppleScriptRunner` wraps `NSAppleScript` on a background queue. `NowPlayingCoordinator`
polls at 1 s idle / 0.25 s while expanded (for a smooth scrubber) and picks whichever
source reports `isPlaying`.

**Critical guard:** check `NSWorkspace.shared.runningApplications` for the bundle ID
*before* scripting — otherwise querying Music.app launches it.

**Permissions:** `NSAppleEventsUsageDescription` in Info.plist; App Sandbox **off**
(this is a personal local app — sandboxing would require Apple-events temporary
exceptions for no benefit). First run triggers a TCC "Atelier wants to control
Music" prompt; handle denial gracefully with a visible "grant access" state rather
than silent nothing.

### Known friction to plan around

Ad-hoc code signing produces a *different* signature every build, so macOS
re-prompts for Automation permission on every rebuild. Mitigation: sign with a free
Apple **Personal Team** in Xcode for a stable identity. Address this in Phase 3, the
moment it starts to bite.

---

## Repository structure

Private repo `aliciaa-20/atelier`, cloned to `~/Downloads/dev-macos/atelier`.

```
atelier/
├── .github/workflows/ci.yml       # xcodebuild build + unit tests on macos-latest
├── .gitignore                     # Xcode/Swift + .DS_Store + xcuserdata
├── .claude/
│   ├── settings.json              # permissions allowlist (xcodebuild, swift, gh)
│   └── commands/build.md          # /build → xcodebuild + launch
├── CLAUDE.md                      # project context for future sessions
├── README.md
├── docs/
│   ├── superpowers/specs/2026-08-31-atelier-notch-design.md
│   └── decisions/0001-mediaremote-unavailable.md
├── Atelier.xcodeproj              # committed (standard practice)
├── Atelier/
│   ├── AtelierApp.swift           # @main, LSUIElement, NSStatusItem
│   ├── Info.plist
│   ├── Atelier.entitlements
│   ├── Notch/{NotchPanel,NotchGeometry,NotchState,NotchController}.swift
│   ├── UI/{NotchRootView,CollapsedPillView,ExpandedPlayerView,Theme}.swift
│   ├── NowPlaying/{NowPlayingInfo,NowPlayingSource,AppleScriptRunner,
│   │               AppleMusicSource,SpotifySource,NowPlayingCoordinator}.swift
│   └── Resources/Assets.xcassets
└── AtelierTests/
    ├── NotchGeometryTests.swift
    ├── NotchStateTests.swift
    └── NowPlayingParsingTests.swift
```

Deployment target **macOS 26.0** (only target machine is hers — unlocks current
APIs and current materials). Swift 6, SwiftUI + AppKit, Swift Testing (`import Testing`),
no third-party dependencies.

---

## Phases

Each phase ends with something runnable, a green test suite, and a commit.

| # | Ships | Claude Code mechanic taught |
|---|---|---|
| 0 | Private repo, Xcode project, CI, app launches with a menu bar icon | plan mode, `gh`, `CLAUDE.md`, `.claude/settings.json` permissions |
| 1 | Black rounded rect perfectly overlaying the real notch | `superpowers:test-driven-development` on `NotchGeometry`; git worktrees |
| 2 | Hover expands/collapses with spring animation | TDD on the state machine; `/simplify` |
| 3 | Real track data from Music + Spotify in the console | Explore subagent; `WebSearch` for grounding; TCC debugging |
| 4 | Full expanded player — artwork, scrubber, transport | `artifact-design` / mockups before coding |
| 5 | Slim pill + auto-peek on track change | hooks (auto-build on Swift file save) |
| 6 | Settings window, launch at login (`SMAppService`) | custom slash commands; `/code-review` |

Backlog after v1: mediaremote-adapter source, file shelf, system HUD replacement,
multi-monitor handling.

---

## Verification

- **Unit tests:** `xcodebuild test -scheme Atelier -destination 'platform=macOS'` —
  covers geometry math, state transitions, AppleScript output parsing. Runs in CI.
- **Visual:** `xcodebuild -scheme Atelier build && open <built .app>`, then confirm
  by eye — the collapsed shape must be indistinguishable from the stock notch.
- **Integration (manual, per phase):** play a track in Music and in Spotify, confirm
  title/artist/artwork/scrubber; hit each transport control; quit both apps and
  confirm neither relaunches; deny Automation permission once and confirm the UI
  says so instead of failing silently.
- **CI:** build + unit tests only. Anything needing TCC or a real notch stays manual.

---

## Blocker to clear first

Alicia must run this herself (needs `sudo`, interactive):

```
sudo xcodebuild -license accept
```

Until then `swift`, `git`, and `xcodebuild` are non-functional shims.
