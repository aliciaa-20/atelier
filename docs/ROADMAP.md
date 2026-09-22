# Atelier — Roadmap

Living checklist of what's shipped and what's next. Each phase ends with
something runnable, a green test suite, and a commit. Source of truth for the
overall plan is [the design spec](superpowers/specs/2026-08-31-atelier-notch-design.md);
this file tracks progress against it.

**Where we are:** Phases 0–8 code-complete, Phases 9 and 10 in progress.
A post-v1 feature request landed out of band from the phase survey — a
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
gradient technique (same ADR). Confirmed on-device this session; the full
manual checklist and the merge are still open.
Phase 9's shelf drag-out preview fix and Phase 10's Wi-Fi/VPN source are
both mid-flight as uncommitted stashes on `main`, not yet resolved.

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
      **Not yet manually verified on-device** — checkbox stays unchecked
      until drag-enter/exit, drop, remove, drag-out, and relaunch
      persistence are actually exercised on real hardware.

  **Two on-device bugs found during manual verification, one open:**
  - Drag-out preview: the custom icon+filename drag ghost wasn't showing
    (fell back to a generic preview). Root-caused to two stacked issues —
    `ShelfDragSourceView` (a raw `NSView`, outside SwiftUI's own gesture
    machinery) needed the same `acceptsFirstMouse` override ADR 0003
    already applied to the root hosting view (confirmed via `os.Logger`
    instrumentation + `log stream`: without it, `mouseDown` never reached
    the view on a not-yet-key panel). That fix confirmed the drag pipeline
    now runs end to end, but the custom image *still* doesn't render —
    current hypothesis is that `lockFocus`/`unlockFocus`-drawn `NSImage`s
    don't reliably serialize as a drag ghost across the Drag Manager's
    out-of-process compositor; swapped to an explicit
    `NSBitmapImageRep`-backed image as the next attempt, **not yet
    verified on-device**.
  - Dropping onto the shelf triggers macOS's own Mission Control
    (confirmed: happens whenever a drag hovers near the menu bar, not
    specific to Atelier) — likely inherent OS behavior tied to the cursor
    reaching the literal top screen edge during any drag, since the
    shelf's whole interaction model requires hovering there. Not
    root-caused yet; no reference app (boring.notch's own `DragDetector`
    uses the identical global-`NSEvent`-monitor approach) shows a known
    fix. Next step if picked back up: try registering the panel as a real
    `NSDraggingDestination` (`registerForDraggedTypes`) instead of pure
    event polling — untested, may or may not suppress it.

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

### ⬜ Phase 12 — Productivity widgets
*Ships: calendar/reminders, quick notes, timers, color picker — each as a
widget plugged into Phase 6's architecture.*
**Depends on Phase 6.**

- [ ] Calendar / reminders (EventKit).
- [ ] Quick notes.
- [ ] Timers / Pomodoro.
- [ ] Color picker.

See [FEATURES.md §6](FEATURES.md#6-productivity-widgets).

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

### ⬜ Phase 17 — Teleprompter / Ghost Mode
*Ships: a scrolling script tab, screen-share/recording invisibility, and a
script library. Voice sync and AI coaching are explicitly later slices of
this same phase, not separate phases — see FEATURES.md §10 for the full
tier breakdown and why.*

- [ ] **Scrolling script tab** — new `NotchPage`, `ScrollView` +
      timer-driven auto-scroll, manual pace control.
- [ ] **Ghost Mode** — `NSWindow.sharingType = .none` on the panel,
      toggleable from the menu bar; verify it actually excludes the window
      from a real screen recording/share, not just assume the API works.
- [ ] **Script library** — folders + search, `ShelfStore`-shaped
      JSON-manifest storage.
- [ ] **Voice-synced scrolling** — `SFSpeechRecognizer` streaming pace
      tracking. Needs its own design pass before starting (real-time audio
      pipeline, latency/accuracy tuning) — don't fold into the same PR as
      items above.
- [ ] *(lower priority)* **AI rehearsal coach** — needs an LLM backend +
      likely Vision-framework posture analysis. Discuss stack/privacy
      tradeoffs before scoping; this is a different trust model than the
      rest of Atelier (network calls).
- [ ] *(lower priority)* **Live meeting captions** — system audio capture
      + speech-to-text.

Credited to [CueNotch](https://cuenotch.com) for the product idea (not
open source, no source pulled — named credit only).

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
