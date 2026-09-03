# Atelier — Roadmap

Living checklist of what's shipped and what's next. Each phase ends with
something runnable, a green test suite, and a commit. Source of truth for the
overall plan is [the design spec](superpowers/specs/2026-08-31-atelier-notch-design.md);
this file tracks progress against it.

**Where we are:** Phases 0–3 complete. **Next up: Phase 4 — the expanded player.**

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

---

## Upcoming

### 🔜 Phase 4 — Full expanded player
*Ships: artwork, title/artist, scrubber, transport controls in the expanded state.*

Goal: hovering the notch shows a native-feeling player, not just a black rect.

- [ ] **Design pass before coding** — mockup the expanded layout (artwork, text,
      scrubber, transport row) so we build to a target, not by trial and error.
- [x] **Artwork** — Spotify returns an artwork **URL** (`ArtworkRef.url`); fetch
      and display it, with a placeholder while loading and on failure.
- [x] **Title / artist** — bind to `NowPlayingInfo`; handle truncation/long titles.
- [x] **Scrubber** — driven by `duration` / `elapsed` (already normalised to
      seconds). Faster poll (0.25 s) while expanded for a smooth bar. Works;
      animation/feel still needs polish.
- [x] **Transport controls** — play/pause, next, previous wired to
      `NowPlayingSource` methods (`playPause`, `next`, `previous`). Confirmed
      responding on-device.
- [x] **Seek** — dragging the scrubber calls `seek(to:)`.
- [x] **Hit-testing** — interactive controls receive events; non-interactive
      regions keep `.allowsHitTesting(false)` scoped correctly (Invariant 4).
      See [ADR 0004](decisions/0004-allowshittesting-scoped-to-spacer.md) —
      it was scoped too broadly and silently ate every click until fixed.
- [x] **Not-playing / no-Spotify state** — a legible empty state, not a blank panel.
- [ ] Manual verification: play a track, confirm artwork/title/artist/scrubber,
      exercise every transport control, drag the scrubber. "(Buttons +
      scrubber confirmed working on-device; artwork/empty-state with a real
      track not yet explicitly confirmed.)"
- [ ] **UI polish** — layout/visuals still rough; scrubber animation needs
      improving. Functionally working, not yet "native-feeling."

Claude Code mechanic to lean on: `artifact-design` / mockups before coding.

### ⬜ Phase 5 — Pill + auto-peek
*Ships: slim pill while music plays; auto-peek on track change, then retract.*

- [ ] **Pill state** — slim always-on sliver hugging the notch while `isPlaying`.
- [ ] **Peek on track change** — detect a track change in the coordinator, drive
      `NotchState.peeking(until:)`, decay back after ~2.5 s unless hovered.
- [ ] Confirm the state machine transitions (`pill` ↔ `peeking` ↔ `expanded` ↔
      `collapsed`) all behave; extend `NotchStateTests` for peek decay.
- [ ] Manual verification: skip tracks and watch it peek then retract; hover
      during a peek and confirm it holds open.

Claude Code mechanic: hooks (auto-build on Swift file save).

### ⬜ Phase 6 — Settings + launch at login
*Ships: a Settings window and launch-at-login.*

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

- **Apple Music source** — a second `NowPlayingSource` conformer. Must not
  require changes outside a new file plus one registration; if it does, the
  protocol is wrong.
- **mediaremote-adapter source** — the Perl bridge for universal coverage
  (including browsers), as an optional source. Weigh against the third-party
  helper that can break on any macOS release. See
  [ADR 0001](decisions/0001-mediaremote-unavailable.md).
- **File shelf** — drag & drop into the notch (see boring.notch / NotchDrop).
- **System HUD replacement** — volume/brightness overlays.
- **Multi-monitor polish** — notchless / external display handling.
