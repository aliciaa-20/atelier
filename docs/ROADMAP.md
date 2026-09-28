# Atelier — Roadmap

Living checklist of what's shipped and what's next. Each phase ends with
something runnable, a green test suite, and a commit. Source of truth for the
overall plan is [the design spec](superpowers/specs/2026-08-31-atelier-notch-design.md);
this file tracks progress against it.

**Where we are:** Phases 0–12 and 14 (camera mirror) shipped, Phase 17 stages 1–3 (teleprompter tab + Ghost Mode + hotkeys) shipped, stage 4 voice sync shipped on its branch (unit-tested, core flow verified on-device; edge-case checks still optional), Phase 16 (Settings window) mostly shipped (Phase 12 so far: color picker + Calendar tab + weather; quick notes/timers not started). Phase 13 (system resource monitor),
Phase 16 (stable signing still open; the menu-bar icon is a placeholder until the app icon exists), and Phase 18 (Liquid Glass notch background) are all 🟨 partial — see
their entries below for what's still open (Phase 18 has one known
unresolved visual bug on close). Phases 9 and 10 detail below is kept as
historical context from when they were in progress.
A feature request landed out of band from the phase survey — a
Home/Shelf tab switcher for the expanded notch, plus real idle-Home content
(date/time + battery %, in its own smaller footprint than the player) —
shipped and manually verified on-device (see
[the design spec](superpowers/specs/2026-09-19-tabbed-navigation-idle-home-design.md)
and [the plan](superpowers/plans/2026-09-19-tabbed-navigation-idle-home.md)).
Further "make it feel more iOS-like" visual polish is deliberately deferred —
see the Backlog.
Phase 9's file shelf sub-project is code-complete (all 6 implementation
tasks reviewed, two real bugs found and fixed) but not yet manually
verified on-device — on-device testing is now underway and has surfaced
two more real bugs, one fixed (drag-out `acceptsFirstMouse`) and two still
open (drag-out preview image, Mission Control triggering on drop) — see
Phase 9's entry below. Phase 6 (Live Activity / widget
architecture) is implemented and confirmed on real hardware: pill/peek/hover/
decay behavior and the Battery widget were tuned live into their final shape
— Battery is deliberately pill-only (`peeksOnChange == false` — no auto-peek,
ever), reads state instantly via a real `IOKit.ps` push notification instead
of polling, always shows a live percent, and briefly interrupts the music
pill (3s) when its own state changes even while music is playing, via a new
`LiveActivityCoordinator.interruptContent` mechanism — see the on-device
notes below for the full list of what was tuned.
**AirPods is disabled, not shipped**: `IOBluetoothDevice.register(forConnectNotifications:)`
crashes the app 100% of the time on this machine's current macOS build (a bug
in Apple's own CoreBluetooth bridge, not something fixable from our code —
see `AirPodsSource.swift`'s doc comment and the commit that disabled it).
Phase 7 (Interaction feel) is implemented, unit-tested, and confirmed
on-device — swipe gestures (open/close, skip forward/backward) and a tuned
"jelly" spring animation are both wired, gated behind
`AtelierSettings.gesturesEnabled`, and were tried on real hardware (see
Phase 7's entry below). 70 tests passing (up from 29 at the end of Phase 5).
**Phase 8 — System HUD replacement is implemented and confirmed on real
hardware**: volume/brightness HUD replacement via a `CGEventTap`
(`MediaKeyInterceptor`), Battery's pill/peek extended with a time-remaining/
time-to-full label, and an Accessibility-permission grant path in the menu
bar. On-device testing surfaced and fixed several real bugs: a CoreAudio
per-channel fallback (some devices don't expose volume on the master
element), a peek/hover-close animation mismatch (peeking now reuses the
same `open`/`close` curves as hovering), hovering during a non-expandable
peek force-opening the now-playing panel (fixed by gating on
`isExpandable`), and the project's ad-hoc code signing losing track of
Accessibility grants across rebuilds (switched to the free Personal Team,
pulling forward part of Phase 16). 85 tests passing (up from 70).
**UI sizing/spacing polish for the volume/brightness peek is explicitly
deferred** — functionally confirmed working, visual polish held for later
per direct request.
Still undecided: whether/how to pursue a fix for the AirPods crash.
**Phase 10 (System alerts) started**: screen recording is the first alert
source shipped — see Phase 10's entry below. Working through the remaining
alerts in order: Focus mode, Wi-Fi/VPN, Bluetooth.
**Phase 11's lock-screen now-playing widget shipped and is merged to
`main`** (PR #9, 6 SDD tasks, 107 tests passing at the time), after two
rounds of on-device visual fixes (positioning, glass background,
hover-morph smoothness, corner-radius consistency, compactness) — see
Phase 11's entry below. **Since then, merged to `main`:** the
visual-identity/tab-bar rebuild (PR #10 — dot-based tab bar, compacted
Idle Home, iOS Control Center-style player sizing, a `ui-review-tahoe`
accessibility/depth/press-feedback pass), the peek-flash bug fix (PR #11),
the real-time audio visualizer (PR #12 — whole-system CoreAudio process
tap, confirmed AirPods-safe, see
[ADR 0012](decisions/0012-whole-system-audio-tap.md)), and a README rewrite
(PR #13). **A further lock-screen widget pass is code-complete on
`worktree-agent-aeef08cc3cfe370e8`, not yet merged**: graceful fade/slide
lock/unlock transitions, a real waveform sharing the notch panel's single
`AudioTap` instance, `MarqueeText` for title/artist, swipe-to-skip (reusing
`NotchGestureInterpreter`/`NotchGestureModifier`, now parameterized so this
card can use its own quicker threshold without affecting the notch panel's
tuned feel — see [ADR 0013](decisions/0013-lock-screen-card-gesture-and-glass.md)),
and a stronger glass treatment adapted from cshariq/Sapphire's public-API
gradient technique (same ADR). Confirmed on-device and merged to `main`.
Phase 9's shelf drag-out preview fix still needs a full reimplementation
(a hand-rolled `NSDraggingSource` attempt was tried and dropped — reuse
NotchDrop's `Transferable`/`FileRepresentation` pattern instead). Phase
10's Wi-Fi/VPN source sits unmerged in the `worktree-live-activity-architecture`
worktree, reported broken and never debugged — neither is an uncommitted
stash on `main` anymore.

---

## Legend

- ✅ done — shipped and committed
- 🔜 next — the current target
- ⬜ planned — not started
- 💤 backlog — not scheduled

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
*Commits `109f51a`..`bc5f737`*
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
- [x] **Extra:** Battery widget shipped and iterated live on real hardware
      into its final shape (charging/low/full via `IOKit.ps`), the first
      non-now-playing widget proving the protocol seam works. Deliberately
      pill-only per direct on-device feedback (`peeksOnChange == false` —
      never auto-peeks; a real percent shows in the pill at all times, not
      just for `.low`); reads state via `IOPSNotificationCreateRunLoopSource`
      (an instant push notification) rather than a poll, which read as
      laggy on-device; briefly interrupts the music pill for 3s when its
      own state changes, via a new `LiveActivityCoordinator.interruptContent`
      mechanism, so it isn't permanently invisible whenever music plays
      (music's own priority still wins the pill the rest of the time).
      **Known open question, not yet decided:** the interrupt is purely
      change-triggered — it does not periodically re-surface while just
      sitting there charging. Whether it should is undecided.
- [x] **Extra:** Now-playing wrapped as the first `LiveActivitySource` without
      rewriting `NowPlayingCoordinator`, proving the seam scales.
- [x] **Manual verification (pill/peek/hover/decay)** — confirmed on real
      hardware: pill shows artwork + waveform, peek fires on track change and
      decays back to pill, hover expands/collapses correctly. Two real bugs
      found and fixed live: a build was accidentally run from the main
      checkout instead of this branch's worktree (not a code bug, but worth
      recording since it looked like one), and the pill's content was
      overflowing its bounds — several on-device tuning passes landed on the
      sizing now in `PillPlayerView` (see its commit history).
- [ ] **AirPods — disabled, not shipped.** `IOBluetoothDevice.register(forConnectNotifications:)`
      crashes the app 100% of the time on-device: `EXC_BREAKPOINT` deep inside
      Apple's own CoreBluetooth bridge (`-[CBPeripheral initWithCentralManager:info:]`,
      reached via `IOBluetoothRegisterForNotifications` enumerating already-paired
      devices). Confirmed independent of call timing (deferring registration one
      run-loop tick made no difference) and independent of a missing
      `NSBluetoothAlwaysUsageDescription` (added to Info.plist regardless — a
      real gap either way — made no difference to the crash). This reads as a
      bug in Apple's framework on this machine's current macOS build, not
      something fixable from Swift. `AirPodsSource` is built, unit-tested
      (classification logic), and wired to conform to the protocol, but is not
      registered in `NotchController`'s source list — see the commit that
      disabled it. **Needs a decision:** wait for an OS update, try an
      alternative Bluetooth API, or drop AirPods from this phase's scope
      entirely and revisit later.
- [ ] **Accepted and deferred: `isExpandable` not wired into hover-gating** —
      `LiveActivityContent.isExpandable` is declared (only now-playing returns
      `true`) but `NotchRootView`'s hover-to-expand path isn't gated on it yet,
      so hovering during a Battery peek (or AirPods, once its crash is fixed)
      still opens the now-playing `ExpandedPlayerView` (which may be
      empty/paused) instead of doing nothing.
      Not a bug to fix this phase — only now-playing has an expanded view so
      far; documenting it now so it isn't rediscovered later as a surprise.
- [x] **Test suite:** 56 tests passing (up from 29 at Phase 5's end), all new logic
      unit-tested (`LiveActivityStack`, `LiveActivityCoordinator` merge/priority/
      dedup logic, `BatteryActivityState` thresholds, `AirPodsKind` classification).
      IOKit/IOBluetooth polling and widget on-device verification remain manual.

See [FEATURES.md §5](FEATURES.md#5-live-activities--system-alerts-extensible-framework).

### ✅ Phase 7 — Interaction feel
*Ships: gestures and physics-based animation. Can run in parallel with
Phase 6.*

- [x] Gesture controls — swipe to open/close, horizontal swipe to seek/skip.
      `NotchGestureInterpreter` is pure, Foundation-only threshold/direction/
      momentum-discarding logic (unit-tested — capability gating,
      direction-dominance lock, momentum discarded, signed accumulation so a
      suppressed gesture followed by a small reversal can't fire the wrong
      action); the AppKit-side `NotchGestureModifier` monitors local +
      global `NSEvent` scroll-wheel streams and feeds it. Wired into
      `NotchRootView`: swipe down/up over the notch reuses the same
      `.hoverStarted`/`.hoverEnded` events hover already dispatches to
      open/close; swipe left/right skips tracks, discretely (no
      scrub-while-swiping), gated on
      `liveActivity.topContent?.isExpandable == true` — reusing Phase 6's
      `isExpandable` flag for the first time since it was declared but left
      unwired. All of it sits behind a new `AtelierSettings.gesturesEnabled`
      toggle, mirroring `peekOnTrackChangeEnabled`. The gesture trigger zone
      is deliberately notch-local, matching both cited reference apps — see
      [ADR 0005](decisions/0005-gesture-trigger-zone-is-notch-local.md).
- [x] Physics-based spring/"jelly" morph animation mimicking real iOS
      Dynamic Island motion. Spring presets consolidated into
      `NotchAnimations.swift` (was scattered inline literals); the open
      spring's `dampingFraction` tuned from 0.8 to 0.65, confirmed on-device
      to read as a genuine elastic overshoot.
- [x] **Test suite:** 70 tests passing (up from 56 at Phase 6's end), all new
      gesture-resolution logic unit-tested in `NotchGestureInterpreterTests`.
- [x] **On-device verification:** confirmed working — swipe open/close and
      swipe skip both function as designed, and the tuned jelly overshoot
      reads correctly. A final whole-branch review (run before the on-device
      pass) caught and fixed one real bug first: the interpreter accumulated
      swipe distance as unsigned magnitude but read direction from the
      latest single sample, so a suppressed gesture followed by a tiny
      opposite-direction jitter could fire the wrong action — fixed by
      switching to signed accumulation, with a regression test added.

See [FEATURES.md §2](FEATURES.md#2-interaction--feel).

### ✅ Phase 8 — System HUD replacement
*Ships: volume/brightness, battery, keyboard backlight, and power-state
HUD replacements.*

Per the design spec ([2026-09-07-phase8-system-hud-design.md](superpowers/specs/2026-09-07-phase8-system-hud-design.md),
confirmed with the user before implementation), this phase scopes to
volume + brightness only — keyboard backlight needs a whole new privileged
XPC-helper subsystem and is deferred to a later phase.

- [x] Volume/brightness HUD replacement — `MediaKeyInterceptor` installs a
      `CGEventTap` on `kCGEventSystemDefined`, structurally adapted from
      monuk7735/mew-notch's `MediaKeyManager` (credited in a source
      comment) per `check-reference-apps-first`. Volume/mute apply via
      public CoreAudio (`VolumeSource`); brightness applies via the
      private `DisplayServices` symbols, resolved at runtime via
      `dlopen`/`dlsym` (`BrightnessSource`) — see
      [ADR 0006](decisions/0006-displayservices-private-api-for-brightness.md)
      for the risk writeup and the fail-open fallback. Both are new
      `LiveActivitySource`s (`NotchLiveActivityPriority.volume = 20`,
      `.brightness = 19`, above now-playing) that publish a transient HUD
      and decay on the same timer as the peek panel itself
      (`NotchController.peekDuration`, 2.5s) — an earlier ~1.3s value
      caused a real on-device glitch, see the fix commit below. Peek
      styling matches the real macOS OSD (icon + capsule bar, no numeric
      label), not this app's usual text+percent peek layout.
- [x] Battery/charging indicator — extended, not new: `BatterySource` now
      also reads `kIOPSTimeToEmptyKey`/`kIOPSTimeToFullChargeKey` from the
      same power-source dictionary it already polls, and
      `BatteryActivityContent`'s peek label gains a "· 2h 14m"-style
      suffix (`TimeFormatting.hoursAndMinutes`, unit-tested; Apple's `-1`
      "still calculating" sentinel renders as no suffix rather than a
      nonsense duration).
- [ ] Keyboard backlight HUD — **deferred**, per the design spec's
      non-goals: needs a privileged XPC helper tool (à la
      TheBoredTeam/boring.notch's `BoringNotchXPCHelperProtocol`), a much
      bigger commitment than this phase's event-tap mechanism.
- [x] Inline volume/output adjuster in the expanded player (2026-09-28,
      out-of-band feature request): tapping the transport row's output icon
      swaps the row for a mute toggle, a `ScrubBarView` volume slider, and
      the output-device picker, in place — mirroring macOS's own Control
      Center Sound module rather than opening a separate popover. Applies
      through two new silent `VolumeSource` methods (`applyDirectly`/
      `setMutedDirectly`) that write CoreAudio directly without
      `publish()`ing — the existing `scrub(toPercent:)`/`toggleMute()` also
      pop the transient system-HUD peek, which double-showed the same level
      on top of this already-visible one (on-device, direct feedback). The
      output-device picker itself is a real `NSMenu` (SwiftUI `Menu` on
      macOS) switching via the same public CoreAudio default-device call
      the system uses — macOS has no public API for embedding the actual
      Control Center routing surface in a third-party window, so this is
      as native as it gets short of that.
- [x] Power state / time remaining — see the Battery bullet above.
- [x] Suppress stock macOS HUDs while ours is shown — falls out of the
      `CGEventTap` callback returning `nil` for a successfully-applied
      change; no separate mechanism needed. Fails open (lets the real key
      event through, so the stock HUD reappears) if the change couldn't
      actually be applied — see `MediaKeyMapping.shouldSuppressEvent`.
- [x] Accessibility-permission grant path — `AccessibilityPermission`
      (`AXIsProcessTrusted()` + a System Settings deep-link) backs a
      conditional "Grant Accessibility Access..." menu-bar item, checked
      live each time the menu opens, matching the existing toggles'
      pattern. `MediaKeyInterceptor` no-ops entirely if permission isn't
      granted, and re-enables its tap if macOS disables it
      (`.tapDisabledByTimeout`/`.tapDisabledByUserInput`) rather than
      leaving media keys silently uncaptured for the rest of the session.
- [x] **Test suite:** 82 tests passing (up from 70 at Phase 7's end) —
      `MediaKeyMapping`'s key-code mapping and fail-open decision, plus
      `TimeFormatting.hoursAndMinutes`'s formatting and "-1"/`nil`
      sentinel handling.
- [x] **Manual verification** — confirmed on real hardware: volume and
      brightness keys apply the real change and show our HUD instead of
      the stock one; hovering during a volume/brightness/battery peek
      correctly resolves to the pill instead of force-opening the
      now-playing panel. Two real bugs found and fixed live (see the
      commits following the design-spec one): CoreAudio's volume-scalar
      property isn't exposed on every device's master element (falls back
      to channel 1 now), and the peek/hover-close animations had quietly
      drifted apart (unified onto the same curves). A third, longer-lived
      bug — Volume/Brightness's peek occasionally flashed the now-playing
      view right before closing — was root-caused later
      (`LiveActivityCoordinator.handle` compared against a single shared
      `lastContentID` instead of a per-source one, so a fallback from
      Volume back to an *unchanged* playing track looked like a new
      identity) and fixed on `worktree-peek-flash-fix`, confirmed
      on-device. Accessibility
      permission itself proved flaky across ad-hoc-signed rebuilds during
      this session — root-caused to code-signature churn, not the
      permission logic itself, and fixed by switching to stable Personal
      Team signing — see
      [ADR 0007](decisions/0007-personal-team-signing.md).
      **Not exercised, still open:** revoking Accessibility access while
      the app is running (does interception stop cleanly).
      **Follow-up polish pass, also confirmed on real hardware:** a
      compact peek size (`compactPeekSize`, 210×notchHeight+26) for
      Volume/Brightness specifically, with a sharp 6pt top corner radius
      matching the stock notch's own (not the softer 14pt "card" radius
      the wider text peek uses) so it reads as still attached to the
      notch. The bar is now click-and-drag scrubbable
      (`ScrubBarView`, live-updates via new `scrub(toPercent:)` methods)
      -- dragging naturally keeps the peek open via the existing decay-
      reschedule-per-publish behavior, no separate pause/resume needed.
      Two more real bugs found and fixed: hovering to grab the bar was
      immediately retracting the peek (the earlier hover-during-peek fix
      needed to no-op entirely for non-expandable content, not force a
      transition), and switching from brightness to volume (but not the
      reverse) took a beat to register -- `LiveActivityStack` snapshots
      each source's priority at upsert time, so `VolumeSource`'s/
      `BrightnessSource`'s new recency-based priority (`SystemHUDOrder`,
      whichever was touched more recently outranks the other) needed
      `LiveActivityCoordinator` to refresh every active source's priority
      on every event, not just the firing source's own — see
      [ADR 0008](decisions/0008-recency-based-system-hud-priority.md).
      Also fixed:
      `PillPlayerView`'s waveform flank reserving a slightly different
      width (18.5pt) than the artwork flank (17.5pt) it's meant to
      mirror.
      **Second follow-up pass, Battery pill specifically:** the
      time-remaining/time-to-full text (previously unreachable dead code
      -- only in `peekView`, which Battery's `peeksOnChange == false`
      means never renders) now shows directly in the pill, text-only on
      both flanks (percent on the right, time on the left; the bolt icon
      was dropped -- icon+percent together needed ~35pt against each
      flank's ~18pt safe budget before the physical notch's dead zone
      swallows content). Both flanks now cap at `maxWidth: 18` so long
      strings (e.g. "12h34m") shrink via `minimumScaleFactor` instead of
      extending into that dead zone -- confirmed on-device as a real,
      asymmetric bug (only the leading-anchored text grows toward the
      notch as it widens; the trailing-anchored text grows away from it).
      Also: charging-state detection was only catching macOS's own
      "Is Charging" flag after a replug, not on the first plug-in --
      `BatterySource` now does staggered re-polls (1s/3s/6s) after each
      IOKit notification instead of one fixed-delay re-poll, to reliably
      catch however long that flag actually takes to settle. Pill corner
      radius also split from `.collapsed`'s (which must stay pixel-matched
      to the real notch) into its own value, now 6/11 — see
      [ADR 0009](decisions/0009-pill-corner-radius-split-from-collapsed.md).

See [FEATURES.md §3](FEATURES.md#3-system-hud-replacement).

### 🔜 Phase 9 — File shelf + AirDrop
*Ships: drag & drop file shelf, AirDrop integration, format converter.*

Decomposed into three sequential sub-projects (AirDrop and the converter
both depend on the shelf existing first) — see
[the design spec](superpowers/specs/2026-09-13-file-shelf-design.md) and
[the implementation plan](superpowers/plans/2026-09-13-file-shelf.md).

- [ ] **File shelf drag & drop** — code-complete via subagent-driven
      development (6 tasks, each with its own task-scoped review, plus a
      final whole-branch review): `NotchState` gained a `.shelf` case and
      `dragEntered`/`dragExited`/`dropCompleted` events; a new
      `Notch/NotchDragDetector.swift` (global `NSEvent` monitors +
      pasteboard `changeCount` tracking, mirroring
      `NotchGestureModifier`'s AppKit boundary) detects a file drag
      entering/exiting/dropping on the notch region; dropped files are
      copied into `~/Library/Application Support/Atelier/Shelf/` and
      tracked by `Shelf/ShelfStore.swift` (plain `[ShelfItem]` array, no
      `swift-collections` dependency) with a lazy 24h expiry sweep;
      `UI/ShelfView.swift` renders the grid with drag-out support. Two
      real bugs found and fixed during review: a test in `ShelfStore`'s
      suite used a real 70-second sleep to differentiate item ages
      (fixed with an injected `addedAt` parameter instead), and the drop
      handler deferred a file copy past `NSItemProvider
      .loadFileRepresentation`'s documented synchronous-validity window
      (fixed by copying to a staging location before hopping actors).
      **Partially verified on-device 2026-09-28**: drag-enter/exit, drop,
      and drag-out all confirmed working (see the bug writeups below).
      Checkbox stays unchecked until remove and relaunch persistence are
      also explicitly exercised.

  **Reworked 2026-09-28** per `check-reference-apps-first`: pulled real
  source from both `Lakr233/NotchDrop` and `TheBoredTeam/boring.notch`
  (`gh api`, not memory) before touching code again. The two references
  actually disagree on drag-out technique — NotchDrop uses SwiftUI's
  `.draggable`/`Transferable` (auto preview from the view), boring.notch's
  *current* `ShelfItemView` hand-rolls `NSDraggingSource` with an explicit
  `ImageRenderer`-rendered preview set on the `NSDraggingItem`. Went with
  the boring.notch pattern since it's proven and closest to what was
  already attempted here. Fixed in `UI/ShelfView.swift`:
  `ShelfItemCell`'s `.onDrag { NSItemProvider(contentsOf:) }` (SwiftUI's
  `.onDrag` can't take a custom image at all) replaced with
  `ShelfDragSourceView`, a raw `NSView: NSDraggingSource` with the same
  `acceptsFirstMouse` override as ADR 0003, a 3pt mouse-move threshold
  before starting a real drag session, and a `SwiftUI ImageRenderer`
  snapshot (icon + filename) set explicitly as the `NSDraggingItem`'s
  contents — sidesteps the earlier `lockFocus`/`unlockFocus` serialization
  failure by not using that API at all. 298/298 tests pass (unaffected —
  this is AppKit plumbing, manual-verification only like the rest of the
  shelf). **Not yet verified on-device.**

  Scoped down deliberately: kept Atelier's existing copy-into-app-support
  storage model rather than boring.notch's newer security-scoped-bookmark
  (no-copy) architecture, and kept single-file/no-multi-select — those are
  real, bigger reworks (boring.notch also supports dropped text/link items,
  not just files) that can be picked up separately if wanted.

  **On-device verification found a second, more fundamental bug** (systematic
  debugging via a screen recording + `AVAssetImageGenerator` contact sheet,
  since a still description wasn't enough to localize it): dropped files were
  being persisted under a **corrupted filename** — `manifest.json` showed
  `"originalFilename":"PDF document.pdf"` for a file actually named
  `Unit4_Prims_Kruskals.pdf`. Root cause: `NotchRootView`'s drop handler
  called `provider.loadFileRepresentation(forTypeIdentifier: "public.item")`
  on an `NSItemProvider` built from the pasteboard's real file `URL`s in
  `NotchDragDetector` — `"public.item"` doesn't exactly match how the file's
  UTI was registered, so the system synthesized a fresh temp copy instead of
  handing back the original, using the UTI's generic type description as the
  filename. Since drag-out re-exports the *already-corrupted* stored file,
  this one bug explained both the "wrong preview" and "wrong filename"
  symptoms on **both** directions (drop-in and drag-out) — not two separate
  bugs. Fixed by cutting the `NSItemProvider` round-trip entirely:
  `NotchDragDetector.draggedFileURLs()` now hands `[URL]` straight to
  `NotchRootView`'s `onDrop` (the real pasteboard `NSURL`s were sitting right
  there the whole time), which still stages a private copy before calling
  `ShelfStore.addFile` but never re-synthesizes a name. **Verified on-device
  2026-09-28: filename retained correctly, drag-out works.**

  Two more findings from that same verification pass, both fixed same day:
  - The shelf showed the file's type icon, not real content. Added
    `Shelf/ShelfThumbnailService.swift`, an actor wrapping
    `QLThumbnailGenerator` with a cache + in-flight-request dedup, adapted
    from boring.notch's own `ThumbnailService` (dropped its
    security-scoped-resource handling — Atelier's shelf files are already
    local copies, not bookmarked references). `ShelfItemCell` now shows the
    real thumbnail once resolved, falling back to the type icon until then.
    **Verified on-device: real content previews (e.g. a PDF's actual first
    page).**
  - Horizontal scrolling didn't engage with many items. Root cause, found by
    comparing against boring.notch's actual `ShelfView` (`gh api`): it uses
    a plain single-row `HStack` in its horizontal `ScrollView`, not a
    multi-row grid. Atelier's `LazyHGrid(rows: [.adaptive])` computed its
    row count from whatever height its parent proposed, which isn't
    reliably bounded to exactly one row here — with enough items it grew
    extra rows that overflowed *vertically* past the visible area (silently
    clipped, since the `ScrollView` is horizontal-only) instead of
    extending horizontally into scrollable space. Switched to a single-row
    `HStack`, matching the reference exactly — a fixed row can only ever
    overflow in the one direction that's actually scrollable. **Verified
    on-device: scrolls correctly with many items.**

  - Mission Control still triggers when a drag hovers near the menu bar.
    Investigated further this pass: boring.notch's `DragDetector` is
    structurally identical to Atelier's `NotchDragDetector` (same
    global-`NSEvent`-monitor approach) and doesn't work around it either.
    This is very likely a WindowServer-level gesture keyed to raw
    screen-edge proximity during *any* drag, independent of which
    app/window owns the drop target — registering the panel as a real
    `NSDraggingDestination` wouldn't change where the cursor physically
    is, so that untested idea was dropped rather than built on spec.
    Treating this as a real OS limitation, not an Atelier bug, unless a
    future reference app turns up an actual workaround.

- [ ] AirDrop integration — sub-project 2, not started.
- [ ] File format converter — sub-project 3, not started.

See [FEATURES.md §4](FEATURES.md#4-file-shelf--related-utilities).

### 🔜 Phase 10 — System alerts as Live Activities
*Ships: system state alerts built on Phase 6's architecture.*
**Depends on Phase 6.**

Phase 6's `LiveActivitySource`/`LiveActivityCoordinator` framework already
existed and needed no changes — this phase is purely adding new conformers,
one at a time, in this order: screen recording, Focus mode, Wi-Fi/VPN,
Bluetooth.

- [x] Screen recording — `ScreenRecordingSource` watches the private
      `CGSIsScreenWatcherPresent()`/`CGSRegisterNotifyProc` pair (event-driven,
      not polled — same shape as `BatterySource`'s `IOKit.ps` notification),
      adapted from Ebullioscopic/Atoll's `ScreenRecordingManager` and
      jackson-storm/dynamicnotch's `SystemScreenRecordingMonitor` per
      `check-reference-apps-first` — their remote-stop-recording feature
      (simulated keystroke injection) was not adopted; this is a status
      indicator, not a controller. `NotchLiveActivityPriority.screenRecording`
      sits above `.nowPlaying` (privacy-relevant, should outrank music).
      Pill-only (`peeksOnChange == false`, matching Battery) — an auto-peek
      on recording start was tried and confirmed on-device as an unwanted
      interruption, not a wanted alert. Small red dot on the pill's trailing
      flank.
- [ ] Focus mode — **skipped for now, not just deferred-by-default.** A
      `check-reference-apps-first` spike into jackson-storm/dynamicnotch's
      `Features/Focus` module found that on macOS 26, `DistributedNotificationCenter`'s
      `_NSDoNotDisturbEnabled/DisabledNotification` and the `duetexpertd` log
      stream are both unreliable (the disable notification often doesn't fire
      at all; the enable one can lack a usable mode identifier) — the only
      reliable source dynamicnotch found is `~/Library/DoNotDisturb/DB/Assertions.json`,
      gated behind **Full Disk Access**, a much broader permission than
      Accessibility. Presented three options (FDA route / best-effort no-new-permission
      route / skip); user chose to skip rather than request FDA. Revisit if
      a cleaner API appears or the user decides FDA is worth it.
- [ ] Wi-Fi / VPN state.
- [ ] Bluetooth — same `IOBluetooth` family already crashing `AirPodsSource`;
      check whether that crash affects this too before starting.
- [ ] Downloads, personal hotspot state alerts.

See [FEATURES.md §5](FEATURES.md#5-live-activities--system-alerts-extensible-framework).

### 🔜 Phase 11 — Now-Playing Live Activity + lock-screen widget
*Ships: now-playing elevated to a first-class Live Activity; lock-screen
surface scope gated on a feasibility spike.*
**Depends on Phase 6.**

- [ ] Elevate now-playing to a first-class Live Activity.
- [x] Real-time audio visualizer — `WaveformView` reacts to real system
      audio instead of `CGFloat.random(in:)`. `AudioTap`
      (`Atelier/System/AudioTap.swift`) creates a whole-system CoreAudio
      process tap (`CATapDescription(stereoGlobalTapButExcludeProcesses:
      [])`), not a per-process tap on Spotify — an earlier design tried
      the per-process approach (matching Ebullioscopic/Atoll's own
      `AudioTap.swift`), but Atoll's own source documents that this
      disturbs the AVRCP session AirPods' pause/skip gesture depends on.
      A whole-system tap was spiked on-device (two independent runs) and
      confirmed AirPods pause/skip unaffected, so the design switched to
      it and dropped the Bluetooth-route guard entirely — see
      [the v2 spec](superpowers/specs/2026-09-20-real-audio-visualizer-design.md)
      [the plan](superpowers/plans/2026-09-20-real-audio-visualizer.md), and
      [ADR 0012](decisions/0012-whole-system-audio-tap.md).
      RMS-per-chunk math lives in `AudioLevels.swift` (pure, unit-tested,
      explicitly `nonisolated` — the project's `SWIFT_DEFAULT_ACTOR_ISOLATION
      = MainActor` setting would otherwise make it `@MainActor`-isolated
      despite having no actor affinity, and `AudioTap`'s realtime IOProc
      callback calling a `@MainActor` function crashed on-device
      immediately — a bug caught by the build, not by the plan). Per
      direct feedback: `PillPlayerView` also got wired to real levels
      (not just `ExpandedPlayerView`, the plan's original scope) so both
      visualizers show the same data; a contrast boost was added to
      `AudioLevels.barHeights` since all 6 bars come from the same ~23ms
      time-sliced buffer and read as too uniform without it. `PeekPlayerView`
      still uses the fake animation (deliberately out of scope). **Real
      bug found during manual verification, not a code bug**: the
      "System Audio Recording Only" TCC permission wasn't granted at all
      for most of this session's testing (`AudioHardwareCreateProcessTap`
      still returns `noErr` and `isRunning` still goes `true` without it —
      it silently produces empty buffers instead of failing outright), and
      even after granting it, CoreAudio took a few minutes to actually
      start delivering real audio data — the waveform sat frozen at its
      default resting state the whole time, which reads identically to
      "broken." `WaveformView`'s nil-`levels` fallback to the fake
      animation only triggers when the tap fails to start at all, not
      when it starts successfully but delivers nothing — worth knowing if
      this ever looks stuck again on a fresh permission grant.
- [ ] **Known issue, unresolved (2026-09-23):** AirPods' pause/skip media-key
      control reportedly stopped working after the real-time visualizer
      landed, specifically when the user hasn't granted the "System Audio
      Recording Only" TCC permission the whole-system `AudioTap` needs —
      it worked with the earlier fake/synthetic waveform. The on-device
      spike above confirmed pause/skip unaffected *with* the permission
      granted; the no-permission case wasn't covered by that spike and
      needs its own check. Requested fix: when system audio access isn't
      granted, fall back to the fake/synthetic waveform entirely (not just
      show a frozen real one) rather than risk breaking AirPods controls.
      Not yet implemented — needs the AirPods-without-permission
      regression reproduced and root-caused first.
- [ ] Synced lyrics.
- [x] Lock-screen now-playing widget — spike confirmed feasible via a
      private CGS space (`SkyLightSpaceOperator`, vendored/hardened from
      Lakr233/SkyLightWindow), same technique Ebullioscopic/Atoll and
      Clayton630/QuartzNotch use, since macOS has no public lock-screen
      widget API. Implemented as 6 SDD tasks on
      `worktree-lockscreen-nowplaying-widget` (all code-complete, reviewed,
      107 tests passing): `SkyLightSpaceOperator` (space delegation,
      hardened against a `dlsym` crash and an unvalidated-space-creation
      bug found in review), `LockScreenManager` (lock/unlock detection),
      `Parallax3DModifier` (artwork tilt), `LockScreenMusicCardView`
      (reusing `ExpandedPlayerView`'s `ScrubberView`), `LockScreenPanelController`
      (window lifecycle/positioning), and final wiring into
      `NotchController`. Iterated twice more after initial on-device
      review against screenshots: (1) the card originally centered
      bottom-screen, which overlapped the login/password field — moved to
      a fixed bottom-left inset instead, since the login field is always
      horizontally centered regardless of macOS version (matches
      QuartzNotch's `LockScreenPanelManager.panelFrame`); swapped the flat
      `.glassEffect()` fill for a blurred/darkened copy of the track's own
      artwork as the background, matching how iOS's own Lock Screen widget
      builds its "glass" from content rather than desktop translucency;
      (2) the hover-expand morph was swapping between two structurally
      different view subtrees (SwiftUI animates that as remove-then-insert,
      not a resize) — rebuilt as one persistent hierarchy with scalar
      properties driving size/spacing, matching Atoll's
      `LockScreenMusicPanel` technique; the corner radius was also
      animating between states (24→30) and drifting out of sync with the
      artwork's own radius mid-hover — fixed to one constant 26pt radius,
      matching both reference apps' `panelCornerRadius`, with the artwork's
      radius kept at a steady ratio of its own size instead of unrelated
      per-state constants. Expanded size cut from 340×200 to 300×148 and
      the transport row went from edge-pinned buttons with a dead gap in
      the middle to a tight centered cluster, matching how compact both
      reference apps keep the expanded state. Merged to `main` via PR #9.
      **Follow-on pass** (code-complete on `worktree-agent-aeef08cc3cfe370e8`,
      not yet merged): graceful `NSAnimationContext` fade/slide on
      lock/unlock instead of an instant `orderOut`; the expanded card now
      shows a real waveform sharing `NotchController`'s single `AudioTap`
      rather than a second CoreAudio process tap; title/artist switched to
      `MarqueeText`; swipe-to-skip added via the notch panel's own
      `NotchGestureInterpreter`/`NotchGestureModifier`; and a stronger
      glass treatment (diagonal sheen, corner highlight/dark pool, gradient
      rim) adapted from cshariq/Sapphire's public-API technique — see
      [ADR 0013](decisions/0013-lock-screen-card-gesture-and-glass.md) for
      both the gesture-tuning and glass decisions. **Still open**: the full
      on-device manual-verification checklist (repeated lock/unlock for
      duplicate-window/crash checks, confirming no overlap with the actual
      Touch ID prompt, not just the password field) and merging this
      worktree branch back to `main`.

See [FEATURES.md §1](FEATURES.md#1-now-playing--live-activity-core).

### 🔜 Phase 12 — Productivity widgets
*Ships: calendar/reminders, quick notes, timers, color picker — each as a
widget plugged into Phase 6's architecture.*
**Depends on Phase 6.**

- [x] Calendar (reminders not built) -- fourth `NotchPage.calendar` tab.
      `Widgets/Calendar/CalendarSource.swift` (read-only EventKit, refreshes
      on `.EKEventStoreChanged`, idle until the tab is first opened),
      `CalendarMath` (pure week math), `WeekdayQuips` (a random funny line
      per weekday), `UI/CalendarPageView.swift` (week strip + agenda, per-
      calendar filter menu, opens on today). Horizontal swipe scrolls
      day-by-day with a stretchy selection indicator (`CalendarScrub` +
      interpreter `.scrub` action; menu-bar toggle "scroll-style swipe" off
      restores one-swipe-per-week via the skip gesture); double-tap a date
      opens the calendar app; panel height fits
      the selected day's events (`NotchLayout`). Tapping opens the user's
      chosen calendar app (menu-bar setting; Calendar.app jumps to the day
      via AppleScript -- `calshow:` is iOS-only). **Verified on-device**
      (2026-09-24): tab, filter, swipe, heights. **Not yet verified:** the
      Calendar.app jump-to-day (needs a one-time Automation grant).
      Scroll swipe and double-tap tried on-device 2026-09-24 (tuned slower
      + crossfade at week rollover).
- [x] Weather -- `Widgets/Weather/` (`WeatherModel` pure + tested,
      `WeatherSource` CoreLocation + Open-Meteo, 30 min cache, no poll loop).
      Glance on idle Home's date line, tap for a detail card (conditions,
      H | L, quip, next 5 days). Calendar week-strip icons were tried and
      dropped as too cluttered. First network feature -- ADR 0015.
- [ ] Quick notes.
- [ ] Timers / Pomodoro.
- [x] Color picker -- `Widgets/ColorPicker/ColorPickerSource.swift` +
      `ColorPickerActivityContent.swift`. `NSColorSampler` triggered from a
      new "Pick a Color..." item in `AtelierApp`'s menu bar, publishing a
      `LiveActivitySource` (priority above `nowPlaying`, below
      `screenRecording` -- see `NotchLiveActivityPriority.colorPicker`)
      that pops a peek (swatch + monospaced hex) for ~2.5s (matched to
      `NotchController.peekDuration`, same reasoning as Volume/Brightness's
      own decay) and copies the hex string to the clipboard. Gated by a new
      "Enable Color Picker" menu toggle (`AtelierSettings.colorPickerEnabled`,
      default on) -- disabling it hides the "Pick a Color..." item entirely
      and no-ops `NotchController.pickColor()`, same "no leftover way in"
      pattern as `shelfEnabled`. Hex formatting
      (`ColorHexFormatting.swift`) is pure and unit-tested; the
      `NSColorSampler`/`NSPasteboard` glue is not, matching this project's
      System/Widgets testing discipline. **Verified on-device** -- eyedropper,
      peek layout, and clipboard copy all confirmed working. Menu bar's
      settings toggles were also regrouped under labeled `Section`s
      (Behavior/Widgets) while adding the "Enable Color Picker" toggle, to
      keep the growing toggle list legible -- flagged as still needing a
      fuller redesign later (deferred, not blocking this item).

See [FEATURES.md §6](FEATURES.md#6-productivity-widgets).

**Weather follow-up (from the 2026-09-24 UI review):** the notch showed 24° while
a menu-bar weather app showed 27°C. Cause: our snapshot was 26 min old (30-min
TTL) plus a different data source. Not a bug. Option if it keeps bugging: drop
the TTL to 15 min (Open-Meteo's `current` updates every 15 min; requests still
happen only when the Home tab is viewed).

### 🟨 Phase 13 — System resource monitor (partial)
*Ships: CPU/GPU/memory/network/disk usage and SMC-based temperature.*
**Depends on Phase 6.**

Only a slice shipped so far: CPU load % and memory-used %, via public
Mach `host_statistics`/`host_statistics64` (`SystemMonitorSource`,
`Atelier/Widgets/SystemMonitor/`), lowest pill priority, 4s poll, plus a
third `NotchPage.systemMonitor` tab (`SystemMonitorPageView.swift`)
alongside Home/Shelf for a full-size view independent of pill priority.
GPU, network, disk, and SMC-based temperature (the parts that need
private/SMC access, per the "Stats" project credit) are **not built**.
**Manual on-device verification not done** — build and the 129-test unit
suite pass, but whether the Mach calls read sane numbers on real
hardware, and whether the pill/tab actually look right, hasn't been
visually confirmed.

See [FEATURES.md §7](FEATURES.md#7-system-resource-monitor).

**From the 2026-09-24 UI review:** memory ring showed a permanent 98-99% red on a
machine with 46% free -- fixed by reading the OS's own free-memory % (see
[ADR 0017](decisions/0017-memory-ring-uses-os-free-percentage.md)).
- [x] Memory ring uses `kern.memorystatus_level`
- [ ] Verify the 70/90 thresholds under real memory pressure on-device
- [ ] Pill percentages ("12%" / "98%") are ~9pt and hard to read; consider a bit more size

### ✅ Phase 14 — Camera mirror mode
*Ships: a camera-preview mirror widget.* Shipped (PR #23, 146 tests pass); verified on-device 2026-09-24: permission
prompt, live mirroring, stop-on-retract and the hold-open setting. See
[ADR 0016](decisions/0016-camera-mirror-preview-layer-tap-to-start.md).

- [x] Camera tab, tap-to-start, denied / no-camera states
- [x] Optional hold-open setting
- [x] Verified on-device
- [x] 2026-09-27: larger `cameraSize` footprint while the mirror is live (was
      undersized relative to other tabs); `frameSize` picks it only when
      `camera.isLive`, so the tab stays compact like every other tab at idle

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

### 🟨 Phase 16 — Settings + launch at login (partial)
*Ships: a Settings window and launch-at-login. (Originally Phase 6; moved
here so the feature survey above ships first.)*

- [x] **Settings window** — surfaced from the `NSStatusItem` menu.
- [x] **Launch at login** via `SMAppService`.
- [x] **Automation-permission UX** — Spotify row in the Permissions pane via `AEDeterminePermissionToAutomateTarget` (only queried while Spotify is running, per Invariant 2; shows "Open Spotify to check" otherwise). Manual on-device check pending.
- [ ] Stable signing identity (free Apple Personal Team) so rebuilds don't
      re-trigger the Automation prompt every time.

Claude Code mechanic: custom slash commands; `/code-review`.

**Parked from the 2026-09-24 UI review (belong here):**
- [x] Menu-bar settings tidy-up: "Camera: keep notch open whil…" is truncated
      -- shorten labels; indent dependent sub-toggles (Calendar swipe, Camera
      hold-open) under their parent
- [x] (note added, not a fix) Permissions pane: after turning Camera off then on in System Settings, the row can stay
      "Denied" until Atelier relaunches (seen on-device 2026-09-24; probably macOS caching the
      camera answer per process). Parked -- add a "may need a relaunch" note or re-read differently.
- [x] Grant All no longer shows for Accessibility alone; window frame autosaved; sidebar can't lose its highlight
- [x] Focus returns to the previous app after Settings closes
- [x] Custom template menu-bar icon (`MenuBarIcon`, drawn in code) — placeholder, to be redrawn from the app icon once that exists

### ⬜ Native-polish backlog (from ui-review-tahoe, 2026-09-24)
*Small, independent items; not a numbered phase.*
- [x] VoiceOver-adjustable scrubbers (playback position, Volume, Brightness)
- [x] Trackpad haptics (`NotchHaptics`: tab switch, mirror toggle, scrub release)
- [x] Symbol/number morphs (`numericText` on Volume/Brightness/monitor %, `.symbolEffect` on transport)
- [x] 9-10pt text bump (Calendar, Weather, Volume/Brightness/ColorPicker pills, and now the teleprompter ring label
      8pt -> 10pt, 2026-09-28 — all scale down via `minimumScaleFactor` if tight); edge gaps: cards share
      `pageHorizontalInset` (26) / `pageBottomInset` (12, = the visible side gap once NotchShape's 14pt edge inset is
      counted) / `cardCornerRadius` (20 - 12 = 8, concentric); peek + HUD panels use one `peekEdgeGap` (9) to every
      edge with the artwork radius concentric (14 - 9); other artwork corners ~22%
- [x] ui-review-tahoe sweep (2026-09-25), batch 1: Shelf remove as a VoiceOver action, labels/decorative hiding on
      peek/pill/HUD/battery/recording/colour-picker views, HUD announcements for VoiceOver (`HUDAnnouncer`), faint text
      raised to AA contrast (`dimmedText`, honours Increase Contrast), tab dots grouped as "Notch tabs", press feedback on
      tab dots/calendar cells/Shelf remove, missing tooltips
- [x] ui-review-tahoe leftovers (2026-09-28): shuffle on/off now also carries a small dot (not colour alone); calendar
      today uses bold weight instead of a colour+ring combo (a ring was tried, rejected on-device for sitting off-centre
      on two-digit dates); tab dots gained Left/Right-arrow keyboard cycling (no visible focus ring -- tried, rejected
      by direct feedback). Also fixed on the same pass: the calendar's white selection indicator was drifting off the
      day-number glyph (a hand-tuned vertical offset guessed from the weekday label's line height) -- now reads the
      real day-number frame via a `PreferenceKey` instead of a constant.
- [x] Done in the `fix/native-polish-pass` branch: real-minute clock, locale-aware
      formats, macOS VoiceOver wording, Reduce Motion, tooltips, Shelf empty state
- [x] 2026-09-27 follow-up: independent "Swipe to skip track" setting, Reduce Motion
      consistency for `SoftPressButtonStyle`, hover-dim feedback on menu-style controls
      (Calendar filter, output-device menu), decorative artwork `accessibilityHidden`,
      lock-screen Next button real press feedback, listening pill VoiceOver value
      (Speaking/Quiet)

---

### 🟨 Phase 17 — Teleprompter / Ghost Mode (stages 1-3 done; voice sync built, core flow verified on-device; later slices remain)
*Ships: a scrolling script tab, screen-share/recording invisibility, and a
script library. Voice sync and AI coaching are explicitly later slices of
this same phase, not separate phases — see FEATURES.md §10 for the full
tier breakdown and why.*

- [x] **Scrolling script tab** — `NotchPage.teleprompter`, time-anchored WPM scroll, control strip
      (reorderable), ring, hand-scroll while paused, Settings pane + file drop. Checked on-device.
- [x] **Ghost Mode** — `sharingType = .none`, menu-bar + Settings toggle. Verified hiding the notch in a
      Google Meet screen share (macOS 27.0); QuickTime/`screencapture`/Zoom not yet tested (ADR 0019 #5).
- [ ] **Script library** — folders + search, `ShelfStore`-shaped
      JSON-manifest storage.
- [ ] **Voice-synced scrolling** (built, core flow verified on-device; edge cases such as >1 min reads, AirPods mid-read, VoiceOver not yet run) — on-device `SFSpeechRecognizer` word tracking (`ScriptMatcher`),
      glide toward the spoken position, "Listening" pill, mic + speech permissions (ADR 0020).
      Built and unit-tested (282 tests); remaining on-device edge checks: recognition on a long script, >1 min read (request restart), pill placement/height, permission grant/deny/revoke, VoiceOver, Reduce Motion, AirPods connecting mid-read, CPU ~0% while waiting, mic indicator off when paused.
- [ ] *(lower priority)* **AI rehearsal coach** — needs an LLM backend +
      likely Vision-framework posture analysis. Discuss stack/privacy
      tradeoffs before scoping; this is a different trust model than the
      rest of Atelier (network calls).
- [ ] *(lower priority)* **Live meeting captions** — system audio capture
      + speech-to-text.

Credited to [CueNotch](https://cuenotch.com) for the product idea (not
open source, no source pulled — named credit only).

---

### 🟨 Phase 18 — Liquid Glass notch background (partial)
*Ships: a Liquid Glass (`.glassEffect(.regular)`) background for
`.expanded`/`.peeking`/`.shelf`, behind a menu-bar toggle.*

`.collapsed`/`.pill` stay flat black regardless (Invariant 7; the pill is
too thin for glass to read as anything but a compression artifact).
Untinted per the `liquid-glass` skill's own tint guidance -- an earlier
full-panel tint read as a colored panel, not clear glass. See
[ADR 0014](decisions/0014-notch-glass-transitions-are-identity-not-crossfade.md)
for why every transition here is `.identity` (snap), not a crossfade —
two real on-device bugs, found by frame-by-frame video. Respects
Accessibility > Display > Reduce Transparency live. Off by default —
`AtelierSettings.glassEffectEnabled` — so it doesn't change the existing
look for anyone who hasn't opted in, plus a `glassIntensity` slider
(plain `.opacity()` on the glass layer, not a tint/crossfade) in the menu
bar's Behavior section.

Also landed alongside this: `peekSize`/`compactPeekSize` now derive their
width from the real, measured notch width (`NotchGeometry`) instead of
disconnected fixed literals, so the peek pill's edges line up with the
physical notch; all peek variants share the notch's own sharp top corner
radius; the close animation was retuned (spring + a brief scale/opacity
dip) to read as retreating into the notch rather than a flat shrink.

**Known issue, unresolved:** a left-edge visual glitch on close
specifically when nothing is playing (closes to `.collapsed` rather than
`.pill`) was still reported after one fix attempt targeting it. Needs an
on-device video of that specific path to diagnose properly — flagged
inline in `NotchRootView.swift` rather than guessed at further.

**Rework parked (2026-09-24):** it reads as transparency, not glass. Research
and options in [docs/research/liquid-glass-apple-guidance.md](research/liquid-glass-apple-guidance.md).

**Menu-bar settings UI is a known placeholder**, not a finished design —
a redesign of the whole menu-bar settings surface (this toggle/slider
included) is planned as separate follow-up work, not blocking this from
landing.

Manually exercised on-device throughout development (build + 129-test
unit suite pass); the known issue above is the one thing not yet
confirmed fixed.

**Parked from the 2026-09-24 UI review (screenshots):**
- [ ] Secondary text (white @ 0.55-0.65: dates, artist, time labels) loses
      contrast on bright wallpapers in glass mode -- raise opacity or add a soft
      shadow when glass is on
- [ ] Top corners of the glass panel look faint/ghosted vs. the black panel's
      crisp inverse curves (the notch-blend illusion weakens)

---

## 💤 Backlog

Items not part of the Phase 6–16 feature survey (see
[FEATURES.md](FEATURES.md)):

- ~~**Apple Music source** — a second `NowPlayingSource` conformer.~~ Shipped
  2026-09-27: `AppleMusicSource` + `MultiNowPlayingSource` (auto-detects
  whichever app is actually playing, `NowPlayingArbiter` is the pure/tested
  arbitration logic) + an iTunes Search API fallback for streaming-track
  artwork (Music.app's AppleScript only exposes artwork for downloaded
  tracks — see [ADR 0022](decisions/0022-apple-music-artwork-itunes-search-fallback.md)).
- **mediaremote-adapter source** — the Perl bridge for universal coverage
  (including browsers), as an optional source. Weigh against the third-party
  helper that can break on any macOS release. See
  [ADR 0001](decisions/0001-mediaremote-unavailable.md).
- **Multi-monitor polish** — notchless / external display handling.
- ~~**iOS-like visual polish for the Home/Shelf tab bar, idle Home, and the
  now-playing player**~~ **Shipped and merged** (PR #10, `main` commit
  `d276fdb`): dot-based tab bar rework (ADR 0011), Idle Home simplified
  (battery line dropped, content height 56pt, width 215pt, 18pt hero
  time), the now-playing player re-tuned toward iOS Control Center sizing,
  the marquee/scrubber title-column fix (150pt), and a `ui-review-tahoe`
  pass (VoiceOver labels, depth shadow, press feedback, best-effort
  keyboard shortcuts). Alicia confirmed hover-retract was no longer
  reproducing at merge time, so it shipped — but the root cause was never
  found; **worth re-verifying if it resurfaces.** See
  [[visual_identity_tabbar_rebuild]] memory for the full diagnosis if it
  does.
- **Volume/brightness scrub bar (`ScrubBarView.swift`) reportedly not
  visually updating** when adjusting volume/brightness — reported once
  during the tab-bar rebuild session, never actually investigated.
- **`worktree-live-activity-architecture`** — an older worktree with 4
  unpushed commits (a Phase 10 slice: Wi-Fi/Bluetooth connect toasts,
  retiring the crashy `AirPodsSource`; plus ADRs 0010/0011 and a now-
  superseded audio-visualizer spec — the shipped visualizer used the v2
  design in ADR 0012 instead). Never opened as a PR; needs a decision on
  whether to revive it. A related but distinct `wip: WiFi/VPN sources`
  stash also sits on `main`, reported broken on-device and never debugged.

## Parked ideas (folded in from the retired STAGES.md, 2026-09-26)

- **VoiceOver-adjustable scrubber:** `ScrubberView` is a raw drag gesture; needs
  `accessibilityValue` + `accessibilityAdjustableAction`. Not built, by choice.
- **Whimsy pass:** the weekday quips were inspired by Claude Code's status words. The same
  voice could go in the System Monitor loading state ("Simmering..."), empty states and the
  weather line. Keep it to a few spots so it stays a quirk, not noise.
- **Weather TTL option** and the Phase 13 threshold check / pill text size (see those phases).
- Per-phase stage checklists (Settings, Camera, Calendar, Teleprompter) lived in `STAGES.md`;
  they are all done and remain in git history (`git log -- STAGES.md`).
- **Stacked live activities on the collapsed pill (from Notchy, 2026-09-26):** show several
  `LiveActivitySource`s at once (e.g. music + timer) instead of one at a time. Best paired with
  timers/Pomodoro; keep the idle cost near zero (see the performance section in `CLAUDE.md`).
- **Synced lyrics** in the now-playing player (also from Notchy). Needs a lyrics source; check
  privacy/licensing before choosing one.
