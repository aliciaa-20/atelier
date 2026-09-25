# 005 — Lock-screen hide uses ease-out

- **Status**: TODO
- **Commit**: a793545
- **Severity**: MEDIUM
- **Category**: Easing & duration
- **Estimated scope**: 1 file, 1 line

## Problem
`LockScreenPanelController.swift:102` `context.timingFunction = CAMediaTimingFunction(name: .easeIn)` starts slowly at the moment the user watches.

## Target
Both show (:79) and hide (:102) use the strong ease-out: `CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)`.

## Boundaries
No duration or distance changes. Don't touch the completion handler.

## Verification
- Mechanical: build + tests green.
- Feel check: lock/unlock; card leaves promptly, no lingering start. Fast lock-unlock-lock still behaves.
- Done when: no `.easeIn` remains in the file.
