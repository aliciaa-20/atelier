# 002 — Use the damped `page` spring for tab switches and non-hover state changes

- **Status**: DONE (unverified on-device)
- **Commit**: a793545
- **Severity**: MEDIUM
- **Category**: Purpose & frequency / Cohesion
- **Estimated scope**: 2 files, ~6 call sites

## Problem
The overshooting hover spring `NotchAnimations.open` (0.65 damping) is also used for tab switching and playback-state changes, which are not hover-driven:
`NotchRootView.swift:224` (tab bar `selectPage`), `:437`, `:552`, `:583`, `:620`, `NotchController.swift:401` (`isPlayingChanged`).
```swift
withAnimation(NotchAnimations.open) { viewModel.selectPage(page) }
```

## Target
Tab selection uses `NotchAnimations.page` (`.spring(duration: 0.4, bounce: 0.15)`). Hover open/close, peek open/close stay on `open`/`close`.

## Steps
1. NotchRootView:224 -> `NotchAnimations.page`.
2. Read :437, :552, :583, :620 and NotchController:401. Change ONLY those whose event is not hover/peek (page selection, `isPlayingChanged`). Leave `hoverStarted`/peek paths.
3. Note in the diff summary which sites were changed and which left.

## Boundaries
Do not touch `open`/`close` values. STOP if a site is ambiguous.

## Verification
- Mechanical: build + tests green.
- Feel check: click between tabs quickly; frame morphs without visible overshoot. Hover-open still jellies.
- Done when: no tab switch uses `open`.
