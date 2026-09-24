# STAGES — Calendar widget (Phase 12)

Branch: `feat/calendar-widget`. Plan: week strip + day agenda, read-only EventKit,
swipe changes week, click opens Calendar.app.

- [x] 1. Page plumbing — `NotchPage.calendar`, tab dot, settings toggle, placeholder view
- [x] 2. Permission + EventKit source — `CalendarPermission`, `CalendarSource`, Info.plist key
- [x] 3. Week strip + agenda UI — `CalendarPageView`, panel height for the page
- [x] 4. Swipe to change week + tap-to-open Calendar.app
- [ ] 5. Docs — FEATURES §6, ROADMAP Phase 12, CLAUDE.md architecture row, README

## Weather (follow-on, after calendar)

Open-Meteo (no key), CoreLocation one-time permission, ~30 min cached fetch (no poll loop).
Shown as icons in the calendar week strip + a compact row on idle Home. Not on the pill.
First network call in the app — note in README/ADR.

- [ ] W1. `WeatherSource` — CoreLocation + Open-Meteo fetch/cache, Info.plist location key
- [ ] W2. Calendar week-strip icons + Home row
- [ ] W3. Docs

Later (separate STAGES): camera mirror (Phase 14) -> Settings (Phase 16) -> teleprompter (Phase 17).
