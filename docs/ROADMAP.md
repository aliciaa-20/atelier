# Atelier — Roadmap

Living checklist of what's shipped and what's next. Each phase ends with
something runnable, a green test suite, and a commit. Source of truth for the
overall plan is [the design spec](superpowers/specs/2026-08-31-atelier-notch-design.md);
this file tracks progress against it.

**Where we are:** Phases 0–4 complete. Phase 5 (pill + auto-peek) is
implemented, unit-tested, and its peek/retract behavior is now confirmed
on-device after a substantial UI polish pass (peek sizing/padding, a
cohesive corner radius, a continuous-loop marquee, a real artwork-loading
latency fix, and per-transition hover animation timing).
**Next up: Phase 6.** (On-device check found that skipping a track currently
opens the full hover/expanded panel rather than the distinct peek — deferred
rather than blocking, see the Phase 5 checklist note below.)

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
