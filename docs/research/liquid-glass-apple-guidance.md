# Liquid Glass — Apple's guidance, and what it means for Phase 18

Researched 2026-09-24 for the parked Phase 18 rework ("make it look like real
glass, not just transparency"). Sources, both from Apple:

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

Tip: `WebFetch` only returns the page title for these (JS-rendered). The raw doc
JSON works: `https://developer.apple.com/tutorials/data/documentation/technologyoverviews/adopting-liquid-glass.json`
and `.../tutorials/data/design/human-interface-guidelines/materials.json`.

## What Apple says

- Glass is a **functional layer for controls and navigation** (tab bars,
  sidebars, buttons) floating *above* content. **"Don't use Liquid Glass in the
  content layer."** Use standard materials (blur, vibrancy) for backgrounds.
- Use it **sparingly** on custom controls; overuse distracts from content.
- **Regular** variant: blurs and adjusts luminosity behind it for legibility;
  use it where there's a lot of text. **Clear** variant: highly translucent, only
  over visually rich backgrounds; add a ~35% dark dimming layer if what's behind
  it is bright.
- Custom backgrounds behind glass "might overlay or interfere" with the effect.
- Group multiple custom glass elements in a **`GlassEffectContainer`** — better
  performance, and it enables morphing between shapes.
- Controls like sliders/toggles turn glass *during interaction*; buttons morph
  into menus/popovers. Use the system button styles instead of hand-rolling.
- Respect Reduce Transparency / Increase Contrast — glass changes appearance.

## Why the current Phase 18 reads as "just transparency"

- The intensity slider is `.opacity()` on the glass layer: it fades the glass,
  it doesn't change the material.
- The notch background is a **full-panel** surface (the content layer, per
  Apple's own rule) sitting over a black base, so there's nothing behind it to
  refract or blur.

## Options to decide between when we pick this up

1. **Glass on controls, not the body (Apple's model, recommended).** Keep the
   notch body black (also preserves Invariant 7). Apply
   `.glassEffect(.regular.interactive())` inside a `GlassEffectContainer` to the
   tab bar, transport buttons, calendar day chips, etc. Remove the opacity slider.
2. **Standard material for the body** (`NSVisualEffectView`/`.ultraThinMaterial`)
   instead of glass — real blur of the desktop behind, cheaper, but changes the
   "notch is black" look.
3. **Keep full-panel glass but use `.clear`** with a dimming layer — closest to
   the current intent, but goes against Apple's guidance and the notch has little
   rich content behind it to show off.

Not covered by these pages: the exact optics (lensing/specular) — the system
material does that; tuning is by eye. Also worth checking before starting: the
`liquid-glass` skill, and WWDC25's Liquid Glass sessions (titles from memory,
unverified).

Existing context: [ADR 0014](../decisions/0014-notch-glass-transitions-are-identity-not-crossfade.md),
ROADMAP Phase 18.
