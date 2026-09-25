# 004 — Replace the fighting close dip with one spring

- **Status**: DONE (unverified on-device)
- **Commit**: a793545
- **Severity**: MEDIUM
- **Category**: Interruptibility
- **Estimated scope**: 1 file (`NotchRootView.swift` ~672-687, 407-409)

## Problem
```swift
withAnimation(.easeOut(duration: 0.18)) { closeFadeOpacity = 0.55; closeScale = 0.85 }
withAnimation(NotchAnimations.close.delay(0.05)) { closeFadeOpacity = 1; closeScale = 1 }
```
The second call retargets the same properties 50ms in, so the dip never completes; it reads as a muddy pulse. The 0.55 opacity also makes the collapsed notch differ from the stock notch (Invariant 7).

## Target
```swift
private func playCloseFadeAnimation() {
    closeScale = 0.96
    withAnimation(NotchAnimations.close) { closeScale = 1 }
}
```
Remove `closeFadeOpacity` state and its `.opacity(closeFadeOpacity)` at ~409. Keep `.scaleEffect(closeScale, anchor: .top)`.

## Boundaries
Do not touch settle animation, background/content transitions, `cornerRadii`/`frameSize`.

## Verification
- Mechanical: build + tests green.
- Feel check: record video of close to pill and close to collapsed (nothing playing, the known left-edge glitch path). Frame-step: no opacity dip, panel retreats smoothly, ends identical to the stock notch. Report whether the left-edge glitch persists.
- Done when: close has a single spring and no opacity change.
