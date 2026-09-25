# 003 — Give page swaps an explicit transition

- **Status**: DONE (unverified on-device)
- **Commit**: a793545
- **Severity**: MEDIUM
- **Category**: Physicality & origin
- **Estimated scope**: 1 file (`NotchRootView.swift` ~262-300)

## Problem
The if/else chain choosing Shelf / SystemMonitor / Calendar / Camera / Teleprompter / ExpandedPlayer has no `.transition`, so swaps get the implicit crossfade, double-exposing two pages while the frame morphs. The outer container is `.transition(.identity)` deliberately (ADR 0014) and must stay so.

## Target
Wrap the page chain in a `Group` and apply, on the Group:
```swift
.transition(.asymmetric(
    insertion: .opacity.combined(with: .scale(scale: 0.97)).animation(.easeOut(duration: 0.2)),
    removal: .opacity.animation(.easeOut(duration: 0.12))))
```
With Reduce Motion (`@Environment(\.accessibilityReduceMotion)`), use plain `.opacity`. Also add `.id(viewModel.currentPage)` on the Group so each page is a distinct view identity.

## Boundaries
Do not touch the background/outer `.transition(.identity)` lines. Do not change page views. If content escapes the clip during the swap (see comments at ~296-318), STOP and report rather than removing clipping.

## Verification
- Mechanical: build + tests green.
- Feel check: screen-record, step through frames; no page ever renders outside the notch shape, no double-exposed pages beyond ~120ms.
- Done when: switching every tab pair looks like a quick settle-in.
