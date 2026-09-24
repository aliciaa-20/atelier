# ADR 0015 — weather: Open-Meteo + CoreLocation, fetch-on-open, no poll loop

- **Status:** Accepted
- **Date:** 2026-09-24

## Context

Idle Home and (briefly) the Calendar tab were meant to show weather. This is
Atelier's **first deliberate network feature** (the only other request is
artwork loading) and its first use of CoreLocation, so the choices are
recorded here rather than left implicit.

## Decision

- **Data:** [Open-Meteo](https://open-meteo.com) `v1/forecast` — free, no API
  key, so nothing to leak or rotate. One request returns current conditions
  plus daily WMO code/high/low (`past_days=6`, `forecast_days=8`).
- **Location:** CoreLocation, one-shot `requestLocation()` at ~3 km accuracy.
  No continuous updates. Coordinates are rounded to 2 decimals (~1 km)
  before leaving the machine. Nothing else is sent; no account, no ID.
- **Refresh:** `WeatherSource.refreshIfStale()` is called from view
  `onAppear` and is a no-op while the cached snapshot is under 30 minutes
  old or a fetch is in flight. **No timer.** The snapshot is persisted in
  `UserDefaults`, so a relaunch shows weather instantly without a request.
  This follows CLAUDE.md's "idle to nothing when not visible" rule.
- **Permission:** Info.plist `NSLocationUsageDescription` /
  `NSLocationWhenInUseUsageDescription`. The app is unsandboxed, so no
  entitlement is needed. If denied, the weather UI hides silently (no nag).
- **Split:** `Widgets/Weather/WeatherModel.swift` (decode, WMO code → symbol +
  quip, staleness, URL building) is pure and unit-tested;
  `WeatherSource` (CoreLocation + URLSession) and `LocationPermission` are
  manual-verification only, like the other system-facing files.
- **UI:** a glance (glyph + temp) on idle Home's date line; tap it for a
  detail card (conditions, H | L, the quip, next five days). Not on the pill.

## Rejected

- **Weather in the calendar week strip.** Built and tried on-device; too
  cluttered next to the event dots, and it forced extra panel height.
  Removed.
- **WeatherKit** — needs a paid developer account and entitlement.
- **IP geolocation** — no permission prompt, but coarse and wrong behind
  VPNs; and a location prompt is one honest tap.
- **A poll loop / background refresh** — costs battery for a value only
  visible when Home is open.
- **Visible quip on the glance** — competed with the date; it lives in the
  tooltip and the detail card.

## Consequences

- Atelier now makes an outbound request to `api.open-meteo.com` (weather
  only). Documented in the README.
- Personal-team signing can lose TCC grants on rebuild (same class as the
  Accessibility issue): if weather stops appearing, re-check
  Privacy & Security → Location Services.
- Quips are per-condition (about ten), not per-temperature or time of day.
