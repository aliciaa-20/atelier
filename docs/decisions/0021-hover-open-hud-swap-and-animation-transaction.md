# 0021 — HUD over the hover-open notch: one `withAnimation` transaction, centred overlay

Date: 2026-09-25 · Status: accepted

## Context
Atelier replaces the system volume/brightness HUD. While the notch was already
hover-open it ignored those changes (no feedback at all) and, because hover
events were dropped while a non-expandable activity was on top, also never
retracted. The fix shrinks the panel to the compact peek size and cross-dissolves
the player into the HUD bar.

## Decisions
1. **Drive the swap from a `withAnimation` transaction, not `.animation(value:)`.**
   `hudShown` mirrors `hudActive` inside `withAnimation(NotchAnimations.hud)`. With
   `.animation(_, value:)` on the panel frame, the panel is centred in its container
   from the *final* size, so the left edge jumped and only the right edge animated
   (a lurch right on the way in, left on the way out). Found from a screen recording,
   not from stills.
2. **The HUD is an `.overlay` on the panel-sized view (before the clip), not a ZStack
   sibling.** The ZStack is as wide/tall as its largest child (the player), so a
   sibling was laid out at player size and clipped, or left-aligned mid-morph.
3. **One critically damped spring (0.4s, no bounce) drives size, opacity, scale and
   blur.** No delayed/staggered fades: the timeline versions felt laggy or showed two
   layers at once. Blur (6pt) + 0.92 scale hides the cross-dissolve, Dynamic Island style.
4. **Retract when the HUD ends and the pointer really is away** (`pointerOverExpandedPanel`
   compares `NSEvent.mouseLocation` with the expanded rect), not on the hover-exit the
   panel shrink itself causes.
5. **Spotify scripts re-check `application "Spotify" is running` inside AppleScript.**
   Spotify posts a playback notification while quitting; Atelier's poll passed the
   Swift-side `isAvailable` check, Spotify exited, and the Apple Event relaunched it.

## Rejected
- Sequenced fades with delays (felt laggy or overlapped).
- `.frame(alignment: .top)` on the whole panel: idle home was sized shorter than its
  content and relied on the centring, so it lost its date/weather row.
- HUD as a ZStack sibling or as an overlay on the player (rode along with the player's
  centring and landed off-screen).
