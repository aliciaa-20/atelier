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

- [ ] W1. `WeatherSource` — CoreLocation + Open-Meteo fetch/cache, Info.plist location key
- [ ] W2. Calendar week-strip icons + Home row
- [ ] W3. Docs

Later (separate STAGES): camera mirror (Phase 14) -> Settings (Phase 16) -> teleprompter (Phase 17).

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
- [ ] S3. `CalendarSource` scrub state + `layoutDay`, wiring, setting + toggle
- [ ] S4. Moving stretchy indicator, Reduce Motion, tuning
- [ ] S5. Docs
