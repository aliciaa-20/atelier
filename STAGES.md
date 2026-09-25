# STAGES — Settings window (Phase 16)

Branch: `feat/settings-window` (merged). Spec: `docs/superpowers/specs/2026-09-24-settings-window-design.md`.
Plan: `docs/superpowers/plans/2026-09-24-settings-window.md`.

- [x] 1. Window shell + `Settings` menu item (`SettingsWindowController`, sidebar)
- [x] 2. General + Appearance panes, launch at login (`SMAppService`)
- [x] 3. Tab order: pure `TabOrder` + tests, `activePages` wiring, Tabs pane
- [x] 4. Widgets + Permissions panes, slim the menu
- [x] 4b. Grant All permissions button (per-row Grant for Calendar/Location)
- [x] 5. Reorderable Home — notch reopens on the first tab in the user's order
- [x] 6. Docs: ADR 0018, README, FEATURES, ROADMAP Phase 16, CLAUDE.md
- [x] Final review fixes: page chosen on open, bounded Location wait, VoiceOver Move Up/Down
- [x] Plain sidebar instead of `NavigationSplitView`; native `.menu` menu-bar menu; Tabs pane as a `List`

**Done — merged as PR #26.** Parked in ROADMAP Phase 16: Camera permission row refresh, Spotify Automation UX, stable signing, template menu-bar icon.

---

(Previous, merged) # STAGES — Native polish pass (from ui-review-tahoe, 2026-09-24)

Branch: `fix/native-polish-pass`.

- [x] Home clock ticks on the real minute (`TimelineView(.everyMinute)`)
- [x] Clock/date use locale-aware format styles (12/24h, date order)
- [x] macOS VoiceOver wording ("Press", not "Double tap")
- [x] Reduce Motion: notch open/close/settle, press feedback, parallax, System Monitor transitions
- [x] `.help()` tooltips on icon-only controls (transport, shuffle, output, tab dots, camera)
- [x] Memory ring: OS free-memory % instead of summed page counts (ADR 0017)
- [x] Shelf empty state in the Camera style; Calendar tooltips
- [ ] **Parked (see ROADMAP):** Phase 16 menu-label tidy + menu-bar icon; Phase 18 glass contrast/corners;
      Phase 13 threshold check + pill text size; Weather TTL option
- [ ] **Parked:** VoiceOver-adjustable scrubber (`ScrubberView` is a raw drag gesture; needs
      `accessibilityValue` + `accessibilityAdjustableAction`). Not built yet, by choice.
- [ ] **Not picked up:** haptics, symbol/number morphs, 9-10pt text, concentric corner radii.

---

# STAGES — Camera mirror (Phase 14)

Branch: `feat/camera-mirror`. Spec: `docs/superpowers/specs/2026-09-24-camera-mirror-design.md`.
Plan: `docs/superpowers/plans/2026-09-24-camera-mirror.md`.

- [x] 1. Page plumbing — `NotchPage.camera`, tab dot, settings toggles
- [x] 2. Hold-open decision (pure) + tests
- [x] 3. Permission + capture source — `CameraPermission`, `CameraMirrorSource`, Info.plist key
- [x] 4. Camera page UI + notch wiring (hold-open, stop on retract)
- [x] 5. UI review pass (`ui-review-tahoe`) done; on-device verification pending Alicia
- [x] 6. Docs — ADR 0016, README, CLAUDE.md, FEATURES §2, ROADMAP Phase 14

---

# STAGES — Calendar widget (Phase 12)

Branch: `feat/calendar-widget`. Plan: week strip + day agenda, read-only EventKit,
swipe changes week, click opens Calendar.app.

- [x] 1. Page plumbing — `NotchPage.calendar`, tab dot, settings toggle, placeholder view
- [x] 2. Permission + EventKit source — `CalendarPermission`, `CalendarSource`, Info.plist key
- [x] 3. Week strip + agenda UI — `CalendarPageView`, panel height for the page
- [x] 4. Swipe to change week + tap-to-open Calendar.app
- [x] 5. Docs — FEATURES §6, ROADMAP Phase 12, CLAUDE.md architecture row, README

## Weather (follow-on, after calendar)

Open-Meteo (no key), CoreLocation one-time permission, ~30 min cached fetch (no poll loop).
Shown as icons in the calendar week strip + a compact row on idle Home. Not on the pill.
First network call in the app — note in README/ADR.

- [x] W1. `WeatherSource` — CoreLocation + Open-Meteo fetch/cache, Info.plist location key
- [x] W2. Home weather glance + tap-for-detail card (5 days). Calendar week-strip icons tried and dropped (too cluttered)
- [x] W3. Docs (ADR 0015, README, CLAUDE.md, FEATURES, ROADMAP)

Camera mirror (Phase 14) and Settings (Phase 16) shipped. Teleprompter (Phase 17) below.

## Teleprompter (Phase 17)

Spec: `docs/superpowers/specs/2026-09-25-teleprompter-design.md`. Plan (stages 1-3): `docs/superpowers/plans/2026-09-25-teleprompter-stages-1-3.md`. ADR 0019. Code for stages 1-3 is on `feat/teleprompter` (235 tests pass); **on-device verification is still pending** (marked below).

- [x] 1. Pure logic (`TeleprompterScript/Scroll/Lines`, hold-open) + script import + script store, tested
- [ ] 2. The tab: control strip, progress ring, reading view, Settings pane — built; **needs on-device check** (strip alignment, ring text fit, speed menu in the panel, every-tab screenshots)
- [ ] 3. Ghost Mode + global hotkeys — built; **Ghost Mode must be verified against a real screen recording (ADR 0019 #5) before it is called done**; hotkeys need a real key-press check
- [ ] 4. Voice sync (`SFSpeechRecognizer`, `ScriptMatcher`, mic/speech permissions, "Listening…" pill) — not started, gets its own plan

Settings (Phase 16) must include **user-reorderable tabs** (asked 2026-09-24). Notes for that plan:
`NotchPage` is a fixed `CaseIterable` order today (home, shelf, systemMonitor, calendar), and
the tab dots + swipe navigation + "always reopens on Home" all assume it -- so the order should
be a persisted list in `AtelierSettings` (pure, testable), with Home pinned first and disabled
tabs skipped. Reorder UI = drag-to-reorder list in the Settings window.

## Ideas parked (try later / maybe a user setting)

- **Scroll-style week swipe (2026-09-24) — IN PROGRESS, see plan stages S1-S5 below.** Instead of one discrete swipe = one week, the
  swipe scrolls continuously: the selected day follows the finger day-by-day and the
  selection indicator stretches/expands (like the tab-bar dot capsule) as it cycles.
  Needs a continuous-progress path in `NotchGestureModifier` (today it only fires discrete
  `skipForward/Backward` actions; the interpreter already computes `progress`, but nothing
  streams it out). Keep the current discrete swipe as the default/fallback; make the new
  one opt-in via a setting. Keep it AppKit-free in the interpreter (Invariant 8).
- **Whimsy pass (2026-09-24).** The weekday quips were inspired by Claude Code's own cute
  status words. Same voice could go in: System Monitor loading state ("Simmering…"),
  empty states, the weather line. Keep it to a few spots so it stays a quirk, not noise.

## Calendar: scroll swipe + double-tap (branch `feat/calendar-widget`)

- [x] S1. Double-tap a date opens the calendar app
- [x] S2. Pure `CalendarScrub` + interpreter `.scrub` + modifier callbacks
- [x] S3. `CalendarSource` scrub state + `layoutDay`, wiring, setting + toggle
- [x] S4. Moving stretchy indicator, Reduce Motion, tuning
- [x] S5. Docs
