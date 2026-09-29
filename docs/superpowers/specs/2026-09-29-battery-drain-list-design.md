# Battery drain list — design

Status: approved in chat 2026-09-29. ROADMAP Backlog, Next-features queue #2.

## Goal

Show which apps are using the most energy, inside the existing System Monitor
tab, sampled only while that view is on screen. Visual only: a relative bar per
app, no numbers on screen. Copy is plain and friendly with a little wit, in the
same voice as System Monitor's status cards and Calendar's empty states.

## Constraints

- No third-party dependencies, no root, no entitlements, no network.
- Lightweight by design (CLAUDE.md): no sampling unless the Energy view is
  visible; the sampling `Task` is cancelled when it goes off screen.
- The panel is fixed-size (Invariant 3): the list shares the tab with the
  gauges via a toggle instead of growing the page.
- Read-only. No quit/kill, no history graph, no notifications.

## Data

Approach chosen: `proc_pid_rusage` with `RUSAGE_INFO_CURRENT` (V6), reading
`ri_energy_nj` (cumulative nanojoules per process). Watts = delta energy /
delta time between two samples. Rejected: shelling out to `top -l 2 -o power`
(spawns a process each sample, ~1s+, text parsing, no per-app grouping) and
CPU time as a proxy (ignores GPU/ANE, could blame the wrong app).

Risk: `ri_energy_nj` is less documented than CPU counters. Verify against
`top -o power` and Activity Monitor on-device before shipping (ADR 0017
lesson); record the result in an ADR if the counter needs caveats.

### `Widgets/SystemMonitor/EnergyMath.swift` (pure, Foundation only, unit tested)
- `watts(previous:current:elapsed:)` — counter delta to watts; clamps
  negative deltas (pid reuse/counter reset) to 0.
- `group(_:)` — folds helper processes under their parent app, ranks
  descending, returns top 5; non-app daemons roll into one "System" row.
- `Tier` — verdict tier from the top app's watts (internal only).

### `Widgets/SystemMonitor/EnergySource.swift` (`@MainActor`, manual verification)
- Walks `proc_listallpids`, calls `proc_pid_rusage` per pid, maps pids to apps
  via `NSRunningApplication`.
- `start()` / `stop()` driven by the Energy segment's `onAppear`/`onDisappear`.
  ~3s interval (`Task` loop, same shape as `SystemMonitorSource`).
- First sample is a baseline only; `hasSample` stays false until the second.
- `@Published` top rows and verdict for the view.

## UI

- `SystemMonitorPageView`: small `Gauges | Energy` segmented toggle at the top.
  Gauges view unchanged.
- `EnergyListView` (`UI/`): verdict line, then up to 5 rows: app icon, name,
  relative bar (scaled to the top app). No watts shown.
- Tokens from `NotchLayout`/`NotchAnimations`; add values there, not inline.
  Bar width changes animate with a named spring and honour Reduce Motion.
- Icon-only controls get `.help()`. Each row has one VoiceOver label, e.g.
  "Safari, highest energy use" / "Mail, about half as much". Decorative bars
  hidden from VoiceOver. Toggle is keyboard reachable.
- Empty/loading states use the shared soft-card style: one SF Symbol, one line.

## Copy (verdict keyed to the top app's watts; no alarming labels)

| Top app | Line |
|---|---|
| under 1 W | "Everyone's napping. Enjoy the quiet." |
| 1–3 W | "[App] is having a light snack." |
| 3–8 W | "[App] is getting peckish." |
| over 8 W | "[App] is eating your battery for breakfast." |
| loading | "Watching who's thirsty…" |
| Atelier in list | row caption "that's me, hi" |

Thresholds are provisional; tune after on-device comparison with `top`.

## Testing

Unit tests (Swift Testing) for `EnergyMath`: watts from known deltas, negative
delta clamp, helper grouping, top-5 ranking and truncation, daemon rollup,
tier boundaries. `EnergySource` and views are manual verification: check
against `top -o power` / Activity Monitor, confirm no sampling when the Energy
segment or the notch is hidden (Activity Monitor CPU for Atelier), screenshots
of both segments.

## Docs to update when shipping

ROADMAP (tick queue #2), README feature list, CLAUDE.md Widgets row, ADR if
`ri_energy_nj` needs caveats.

## Revisions after on-device review (2026-09-29)

The first build read as cluttered and clipped the gauges, so the shipped
design differs from the sections above:

- **Switch:** a small corner icon (bolt / speedometer) instead of a segmented
  `Gauges | Energy` control, which cost vertical space and clipped "Memory".
- **Rows:** top **3**, `.regular` (Dock) apps only; no "System" row, no
  background agents, no "that's me, hi" caption.
- **Bars:** scaled against `max(top, 3 W)` (`EnergyMath.barFraction`) so an
  idle Mac shows short bars that agree with "napping".
- **Loading card:** "Finding the battery hogs…", no icon.
- **Copy/contrast:** secondary text uses `dimmedText()`; the switch has hover
  feedback. Sampling also stops explicitly when the notch collapses.
- **Known limit:** only ~65% of pids are readable without root, so
  WindowServer never appears (ADR 0029).
