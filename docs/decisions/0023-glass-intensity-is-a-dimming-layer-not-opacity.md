# ADR 0023 — Glass intensity dims, it doesn't fade

- **Status:** Accepted (partial port -- see Consequences)
- **Date:** 2026-09-28

## Context

The 2026-09-24 UI review parked a complaint: the glass panel's top corners
look faint/ghosted next to the flat black panel's crisp inverse curves,
weakening the notch-blend illusion.

Root cause: `AtelierSettings.glassIntensity` (the Settings slider) was
applied as a plain `.opacity()` on the whole glass layer, corners included.
Fading a translucent material's edges reads as *more* transparency, not
less glass.

## Decision

- The `NotchShape` glass layer (`.glassEffect(.regular, in: NotchShape(...))`)
  always renders at full material strength now -- no `.opacity()` on it.
- `AtelierSettings.glassIntensity` instead drives a `Color.black.opacity(glassIntensity * 0.35)`
  overlay on top of the glass -- Apple's own documented technique ("add a
  ~35% dark dimming layer if what's behind it is bright"), repurposed here
  since Atelier's glass variant is always `.regular`.
- A thin light rim (`shape.stroke`, brighter at the top fading to nothing
  at the bottom) restores the crisp top-corner definition the flat panel
  gets for free from its opaque fill.
- The background is pulled into its own `Equatable` `GlassPanelBackground`
  view so SwiftUI can skip re-invoking it on unrelated re-renders (audio
  levels publish many times a second while music plays), and marked
  `.allowsHitTesting(false)` as the invariant-correct treatment for a
  purely decorative layer.

## Consequences

- The "top corners look faint/ghosted" symptom should be gone now that the
  material itself is never faded -- confirmed on-device 2026-09-28.
- **This is a partial port.** A separate branch (`feat/liquid-glass-body-dimming-fix`)
  built this same change alongside a pill entrance animation and a
  `glassBackgroundActive` environment key for glass-aware secondary text,
  then hit a real, still-unresolved hover-oscillation bug (the panel
  genuinely opening/closing in a tight loop while hovering, not a
  rendering glitch -- see that branch's own history for four separate
  failed fix attempts). That bug was confirmed to reproduce independent of
  this specific change (against a plain, undimmed `.glassEffect()` too),
  so it isn't blocking this corner fix, but it also isn't fixed by it.
  Deliberately left out of this port: the pill entrance animation (its own
  gating looks broken -- gated on `glassBackgroundActive`, which is never
  true during `.pill` per Invariant 7, so it can't actually fire as
  written) and the `glassBackgroundActive` environment key (this repo's
  glass-mode text contrast fix took a different approach -- reading
  `AtelierSettings.glassEffectEnabled` + `\.accessibilityReduceTransparency`
  directly at each call site -- see `DimmedText.swift`).
- The hover-oscillation flicker remains open, tracked for a future pass.
