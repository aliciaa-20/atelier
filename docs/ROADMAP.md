# Atelier — Roadmap

Living checklist of what's shipped and what's next. Each phase ends with
something runnable, a green test suite, and a commit. Source of truth for the
overall plan is [the design spec](superpowers/specs/2026-08-31-atelier-notch-design.md);
this file tracks progress against it.

**Where we are:** Phases 0–6 complete. Phase 6 (Live Activity / widget
architecture) is implemented, unit-tested with 56 tests passing (up from 29),
and ships two widgets (Battery, AirPods), both unit-tested, plus the generalized
`LiveActivitySource`/`LiveActivityContent` protocol for later phases. Pill
display with artwork + mini waveform is implemented and unit-tested, with
on-device confirmation still pending (no display access in this session).
**Next up: Phase 7 — Interaction feel** (gestures and physics-based animation),
the next item in the reference-app-informed feature survey (see
[FEATURES.md](FEATURES.md)).

---

## Legend

- ✅ done — shipped and committed
- 🔜 next — the current target
- ⬜ planned — not started
- 💤 backlog — after v1

---

## Completed

### ✅ Phase 0 — Scaffold
*Commit `7c28bb5`*

- Private repo, Xcode project, CI (build + unit tests on `macos-latest`).
- App launches as an `LSUIElement` (no Dock icon) with an `NSStatusItem` menu.
- Claude Code mechanics: plan mode, `gh`, `CLAUDE.md`, `.claude/settings.json` permissions.

### ✅ Phase 1 — Notch overlay
*Commit `a78272e`*

- Black rounded rect perfectly overlaying the real notch.
- Pure `NotchGeometry` (screen → notch rect), unit-tested — see `NotchGeometryTests`.
- Collapsed state visually indistinguishable from the stock notch (Invariant 7).
- Claude Code mechanics: TDD on `NotchGeometry`; git worktrees.

### ✅ Phase 2 — Hover expand/collapse
*Commit `8f89ff3`*

- Hover expands and collapses the notch with spring animation.
- Pure `NotchState` state machine (`reduce(event:) -> NotchState`), unit-tested — see `NotchStateTests`.
- Panel sized once to the maximum expanded footprint; only SwiftUI content animates (Invariant 3).
- Claude Code mechanics: TDD on the state machine; `/simplify`.

### ✅ Phase 3 — Real Spotify data end-to-end
*Commit `90506b3`*

- Real now-playing data from Spotify flowing through to the UI.
- `NowPlayingSource` protocol with `SpotifySource` conforming; `AppleScriptRunner`
  wraps `NSAppleScript` off the main queue; `NowPlayingCoordinator` polls and drives state.
- `SpotifyOutputParser` normalises Spotify's mixed time units at the parsing
  boundary (`duration` ms, `player position` float seconds — Invariant 5),
  covered by `SpotifyOutputParserTests`.
- Running-app guard before scripting so we never launch Spotify unprompted (Invariant 2).
- Claude Code mechanics: Explore subagent; `WebSearch` for grounding; TCC debugging.

> **Scope note:** v1 is Spotify-only. The `NowPlayingSource` seam stays, but only
> `SpotifySource` conforms for now. See
> [ADR 0002](decisions/0002-spotify-only-for-v1.md).

### ✅ Phase 4 — Full expanded player
*Commit `1bd1e4a`*

- Artwork (with placeholder while loading and on failure), title/artist,
  scrubber, transport controls (play/pause, next, previous), and seek all
  wired to `NowPlayingSource`; a legible not-playing/no-Spotify empty state.
- Design pass done against reference apps (boring.notch's `MusicPlayerView`)
  rather than from first principles — see `check-reference-apps-first`.
- Real hit-testing bug fixed: `.allowsHitTesting(false)` was scoped to the
  whole root `VStack` instead of just the `Spacer`, silently eating clicks
  across the whole player since Phase 4 began. See
  [ADR 0004](decisions/0004-allowshittesting-scoped-to-spacer.md).
- Layout redesigned multiple passes (panel/artwork sizing, marquee title
  scroll, waveform, shuffle, output-device switching).
- Claude Code mechanics: reference-app lookups; ADR 0003/0004 debugging.

> **Verification note:** transport controls and scrubber were confirmed
> responding on-device. Artwork rendering and the empty state were not
> explicitly re-confirmed against a live track after the Phase 4 redesign —
> worth a quick on-device look before calling the layout fully settled.

---

## Upcoming

### 🔜 Phase 5 — Pill + auto-peek
*Ships: slim pill while music plays; auto-peek on track change, then retract.*

- [x] **Pill state** — slim always-on sliver hugging the notch while
      `isPlaying`, driven by real Spotify state.
- [x] **Peek on track change** — track change drives `NotchState.peeking`,
      decays back after ~2.5 s unless hovered; reuses the persistent
      panel/state machine with a dedicated `PeekPlayerView` rather than a
      second window (a `DynamicNotchKit` popover was tried first and
      visually conflicted with the main panel on-device).
- [x] State machine transitions (`pill` ↔ `peeking` ↔ `expanded` ↔
      `collapsed`) covered by `NotchStateTests`.
- [x] **Extra, ahead of Phase 6:** `AtelierSettings` + a menu-bar toggle for
      "Peek on Track Change."
- [x] **Manual verification (peek/retract)** — skipped tracks repeatedly
      on-device and confirmed the peek appears and auto-retracts correctly.
- [ ] **Manual verification (hover-holds-open)** — hover during a peek and
      confirm it holds open instead of retracting. **Deferred:** on-device
      check on 2026-09-04 showed skipping a track opens the full
      hover/expanded panel instead of the distinct peek UI, so this couldn't
      be exercised as designed. Not a blocker for Phase 6, but worth
      revisiting — likely a hover-region or state-machine transition
      overlapping the peek trigger.
- [x] **Extra, beyond the original checklist:** a full UI polish pass on
      the peek pill — corner radius unified to a single cohesive 14pt
      (was mismatched 14/20, inherited from the expanded player), padding
      tightened and balanced on all edges, artwork enlarged and its own
      corner radius reduced to read as concentric with the panel, waveform
      shrunk to fit, and a real fix for ~1.5s artwork-load latency (two
      independent network fetches — the visible `ArtworkView` and the
      waveform's `ArtworkColorLoader` — were racing on the same URL; both
      now share one fetch via a new `ArtworkImageCache`). The marquee
      itself was rebuilt from a snap-back-to-start cycle into a genuine
      continuous ticker loop, applied to both title and artist. Hover-close
      also got its own, more damped animation, separate from hover-open,
      via explicit per-trigger `withAnimation` calls replacing one blanket
      state-based modifier.
- [x] **Extra, added after this session's roadmap reorder:** peek now also
      fires on a play/pause toggle, not just a track change (a new
      `playbackToggled` event, reusing `trackChanged`'s resting-state-only
      reducer logic — unit-tested in `NotchStateTests`). The peek's decay
      animation was also switched from the snappy open-speed spring to the
      same slower, more damped one used for hover-close, so it retracts
      smoothly instead of snapping shut.

Claude Code mechanic: hooks (auto-build on Swift file save).

### ✅ Phase 6 — Live Activity / widget architecture
*Commit `5eac25f`*
*Ships: an extensible `LiveActivitySource`/`LiveActivityContent` protocol that
later phases plug into, instead of each bolting a new surface onto `NotchState`
directly.*

- [x] `check-reference-apps-first` spike against jackson-storm/dynamicnotch and
      Clayton630/QuartzNotch source before designing — foundational architecture
      for most of the rest of the backlog.
- [x] Generalize `NotchState`'s peek/pill mechanism into an extensible
      Live Activity concept via `LiveActivityStack` (pure, priority-sorted) +
      `LiveActivityCoordinator`, preserving the existing event vocabulary without
      modifying `NotchState.swift` itself.
- [x] Define the `LiveActivitySource`/`LiveActivityContent` protocol (mirrors
      `NowPlayingSource`'s seam) that other phases conform to.
- [x] **Extra, requested mid-implementation:** Resting `.pill` state, previously
      rendering only the bare notch shape, now shows artwork + mini waveform via
      new `PillPlayerView`.
- [x] **Extra:** Battery widget shipped (charging/low/full alerts via `IOKit.ps`),
      the first non-now-playing widget proving the protocol seam works.
- [x] **Extra:** AirPods widget shipped (connection status + best-effort battery
      percentage via isolated, undocumented-API helper), second widget, built
      after Battery per explicit user request.
- [x] **Extra:** Now-playing wrapped as the first `LiveActivitySource` without
      rewriting `NowPlayingCoordinator`, proving the seam scales.
- [ ] **Manual verification (AirPods on-device)** — no AirPods hardware was
      available this session, so even a first connection test hasn't happened yet.
      **Deferred:** on-device check needed for full AirPods implementation.
- [ ] **Manual verification (pill/peek/hover/decay)** — the generalized pill/peek
      state wiring (Task 6's NotchController rewiring) is implemented and
      unit-tested, but on-device confirmation of the full interaction flow
      (pill → hover-expand → peek → decay → retract, with proper hover-holds
      behavior) is pending. **Deferred:** no display access in this session.
- [ ] **Manual verification (Battery widget peek behavior)** — the Battery widget's
      charging/low/full alerts are unit-tested for state thresholds, but the visual
      peek/retract behavior under real charging state transitions needs on-device
      confirmation. **Deferred:** no display access in this session.
- [x] **Test suite:** 56 tests passing (up from 29 at Phase 5's end), all new logic
      unit-tested (`LiveActivityStack`, `LiveActivityCoordinator` merge/priority/
      dedup logic, `BatteryActivityState` thresholds, `AirPodsKind` classification).
      IOKit/IOBluetooth polling and widget on-device verification remain manual.

See [FEATURES.md §5](FEATURES.md#5-live-activities--system-alerts-extensible-framework).

### ⬜ Phase 7 — Interaction feel
*Ships: gestures and physics-based animation. Can run in parallel with
Phase 6.*

- [ ] Gesture controls — swipe to open/close, horizontal swipe to seek/skip.
- [ ] Physics-based spring/"jelly" morph animation mimicking real iOS
      Dynamic Island motion.

See [FEATURES.md §2](FEATURES.md#2-interaction--feel).

### ⬜ Phase 8 — System HUD replacement
*Ships: volume/brightness, battery, keyboard backlight, and power-state
HUD replacements.*

- [ ] Volume/brightness HUD replacement.
- [ ] Battery/charging indicator.
- [ ] Keyboard backlight HUD.
- [ ] Power state / time remaining.
- [ ] Suppress stock macOS HUDs while ours is shown.

See [FEATURES.md §3](FEATURES.md#3-system-hud-replacement).

### ⬜ Phase 9 — File shelf + AirDrop
*Ships: drag & drop file shelf, AirDrop integration, format converter.*

- [ ] File shelf drag & drop.
- [ ] AirDrop integration.
- [ ] File format converter.

See [FEATURES.md §4](FEATURES.md#4-file-shelf--related-utilities).

### ⬜ Phase 10 — System alerts as Live Activities
*Ships: system state alerts built on Phase 6's architecture.*
**Depends on Phase 6.**

- [ ] Focus mode, screen recording, downloads, personal hotspot, Bluetooth,
      Wi-Fi, VPN state alerts.

See [FEATURES.md §5](FEATURES.md#5-live-activities--system-alerts-extensible-framework).

### ⬜ Phase 11 — Now-Playing Live Activity + lock-screen widget
*Ships: now-playing elevated to a first-class Live Activity; lock-screen
surface scope gated on a feasibility spike.*
**Depends on Phase 6.**

- [ ] Elevate now-playing to a first-class Live Activity.
- [ ] Real-time audio visualizer.
- [ ] Synced lyrics.
- [ ] Lock-screen now-playing widget — **spike first**: macOS has no public
      lock-screen widget API for third-party apps; confirm what reference
      apps actually built before committing to scope.

See [FEATURES.md §1](FEATURES.md#1-now-playing--live-activity-core).

### ⬜ Phase 12 — Productivity widgets
*Ships: calendar/reminders, quick notes, timers, color picker — each as a
widget plugged into Phase 6's architecture.*
**Depends on Phase 6.**

- [ ] Calendar / reminders (EventKit).
- [ ] Quick notes.
- [ ] Timers / Pomodoro.
- [ ] Color picker.

See [FEATURES.md §6](FEATURES.md#6-productivity-widgets).

### ⬜ Phase 13 — System resource monitor
*Ships: CPU/GPU/memory/network/disk usage and SMC-based temperature.*
**Depends on Phase 6.**

See [FEATURES.md §7](FEATURES.md#7-system-resource-monitor).

### ⬜ Phase 14 — Camera mirror mode
*Ships: a camera-preview mirror widget.*

See [FEATURES.md §2](FEATURES.md#2-interaction--feel).

### ⬜ Phase 15 — Dev-agent session monitoring
*Ships: live session tracking and permission-approval UI for Claude
Code/Cursor/Codex. Standalone subsystem — sequenced last as the most novel
and highest-effort item in the backlog.*

- [ ] Live session tracking (duration, tool activity, context/rate-limit
      progress).
- [ ] Permission-approval UI (Allow Once/Always/Deny) from the notch.
- [ ] Hook-install + IPC bridge design (à la AgentPulse's Unix domain
      socket bridge).

See [FEATURES.md §8](FEATURES.md#8-dev-agent-session-monitoring).

### ⬜ Phase 16 — Settings + launch at login
*Ships: a Settings window and launch-at-login. (Originally Phase 6; moved
here so the feature survey above ships first.)*

- [ ] **Settings window** — surfaced from the `NSStatusItem` menu.
- [ ] **Launch at login** via `SMAppService`.
- [ ] **Automation-permission UX** — a visible "grant access" path when TCC is
      denied, re-checkable from Settings.
- [ ] Stable signing identity (free Apple Personal Team) so rebuilds don't
      re-trigger the Automation prompt every time.

Claude Code mechanic: custom slash commands; `/code-review`.

---

## v1 done means

- Hover → full player; music playing → pill; track change → peek then retract.
- Spotify data correct: artwork, title/artist, scrubber, working transport.
- Neither Spotify nor any media app is launched by us unprompted.
- Denied Automation permission shows a clear state, never a silent blank.
- Green unit suite (geometry, state, parsing) in CI; manual integration checks
  pass on the target MacBook.

---

## 💤 Backlog — after v1

Items not part of the Phase 6–16 feature survey (see
[FEATURES.md](FEATURES.md)):

- **Apple Music source** — a second `NowPlayingSource` conformer. Must not
  require changes outside a new file plus one registration; if it does, the
  protocol is wrong.
- **mediaremote-adapter source** — the Perl bridge for universal coverage
  (including browsers), as an optional source. Weigh against the third-party
  helper that can break on any macOS release. See
  [ADR 0001](decisions/0001-mediaremote-unavailable.md).
- **Multi-monitor polish** — notchless / external display handling.
