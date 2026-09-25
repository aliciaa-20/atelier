# 001 — Consolidate inline springs into NotchAnimations tokens

- **Status**: DONE (verified on-device 2026-09-25)
- **Commit**: a793545
- **Severity**: MEDIUM
- **Category**: Cohesion & tokens
- **Estimated scope**: ~8 files, mechanical

## Problem
About 12 near-identical `.spring(response:dampingFraction:)` literals are typed inline, e.g.
`NotchRootView.swift:563` `.spring(response: 0.3, dampingFraction: 0.8)`,
`NotchTabBar.swift:61` same, `CalendarPageView.swift:197`, `LiveActivityCoordinator.swift:145`
`(0.25, 0.8)` and `:152` `(0.6, 0.92)` (hand-retyped copies of `open`/`close`),
`ScrubBarView.swift:43` and `ExpandedPlayerView.swift:346` `(0.3, 0.7)`,
`ExpandedPlayerView.swift:213` / `WeatherDetailView.swift:120` `(0.2, 0.6/0.7)` for press.

## Target
Add to `Atelier/UI/NotchAnimations.swift` (all Reduce-Motion aware via the existing private `reduceMotion`):
```swift
/// Small state changes: tab dots, week shifts, toggles. Damped, no overshoot.
static var standard: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.85) }
/// Tab/page changes and non-hover state changes: subtle bounce only.
static var page: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.15) }
/// Press feedback on buttons: fast, slightly bouncy.
static var press: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.2, dampingFraction: 0.7) }
/// Drag-handle grow/shrink (scrubber thumb).
static var grab: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.75) }
```
`open`/`close` stay unchanged.

## Repo conventions
`NotchAnimations` (enum, static vars) is the single home. Exemplar: `NotchAnimations.open`.

## Steps
1. Add the four tokens above under `settleSpringBack`.
2. Replace: NotchTabBar:61, NotchRootView:563/570, CalendarPageView:197 -> `NotchAnimations.standard`;
   LiveActivityCoordinator:145 -> `NotchAnimations.open`, :152 -> `NotchAnimations.close`;
   ExpandedPlayerView:213, WeatherDetailView:120 -> `NotchAnimations.press` (keep the existing `reduceMotion ? nil :` gating where present);
   ScrubBarView:43, ExpandedPlayerView:346 -> `NotchAnimations.grab`.
3. Leave Calendar-specific springs (CalendarPageView:149,159), SystemMonitor, Teleprompter, Settings panes untouched.

## Boundaries
No value changes beyond the mapping above; no new dependencies; if a line has drifted, STOP and report.

## Verification
- **Mechanical**: `xcodebuild -scheme Atelier -configuration Debug build`; `xcodebuild test -scheme Atelier -destination 'platform=macOS'` all green.
- **Feel check**: tab dots, week shift, scrubber grab, play/pause press feel the same as before (values were near-identical).
- **Done when**: `grep -rn "\.spring(response" Atelier/UI Atelier/Notch` shows only NotchAnimations plus the Calendar/Monitor/Parallax specials.
