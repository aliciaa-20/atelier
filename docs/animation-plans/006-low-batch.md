# 006 — Reduce Motion on settle, waveform retarget, parallax coalescing

- **Status**: DONE (verified on-device 2026-09-25)
- **Commit**: a793545
- **Severity**: LOW
- **Category**: Accessibility / Performance
- **Estimated scope**: 3 files

## Problem and Target
1. `NotchRootView.swift:664` `playSettleAnimation` tucks to `settleScale = 0.55` regardless of Reduce Motion. Target: `guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }` at the top.
2. `WaveformView.swift:35` `.animation(.easeInOut(duration: 0.2), value: scales[index])` is retargeted every 0.12s (`timerInterval`), so it never finishes. Target: `.animation(.easeOut(duration: 0.12), value: scales[index])` (duration == timer interval).
3. `Parallax3DModifier.swift:36` starts a new `interactiveSpring(response: 0.1, dampingFraction: 0.5)` per mouse event. Target: `dampingFraction: 0.8` (0.5 rings on rapid retargeting) and keep scale 1.04.

## Boundaries
Only these three edits. STOP on drift.

## Verification
- Mechanical: build + tests green.
- Feel check: waveform bars smooth, no stutter; parallax follows the cursor without jitter; Reduce Motion on = no tuck on Space change.
