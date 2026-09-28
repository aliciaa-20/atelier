# macOS 27 / iOS 27 design tokens — raw values

Pulled directly from Apple's official **macOS 27 UI Kit** (Figma Community,
verified "Apple" / Figma Partner account, tag `#liquid-glass`):
<https://www.figma.com/community/file/1651309434229735362/macos-27>

...and its companion **iOS and iPadOS 27 UI Kit** (same Apple account):
<https://www.figma.com/community/file/1651309003795292092/ios-and-ipados-27>.
Working copy: `https://www.figma.com/design/15cSDNvO7EhJhkngbbNpNV/iOS-and-iPadOS-27--Community-`.

**No "Dynamic Island" component or token group exists in the iOS kit** —
searched Assets and every Dimensions/Kit group, nothing. The island is
OS-owned system chrome; apps get it through the Live Activity API, they
don't draw its shape themselves, so Apple has nothing to publish for it.
This confirms Atelier's own approach (deriving panel geometry from
`NotchGeometry`'s measured screen-corner APIs rather than a fixed spec) is
the right pattern, not a gap to fill — there's nothing upstream to match
against beyond what's already being measured live.

**The Liquid Glass material recipe below is identical, value-for-value,
between the macOS and iOS/iPadOS kits** — one shared cross-platform
material spec, not something to tune differently per platform.

The Community preview only exposes the Cover page via the API/MCP — the
Assets/Variables panels only resolve once the file is duplicated into your
own Drafts ("Open in Figma" → "Make a copy of this file"). Our working copy:
`https://www.figma.com/design/cYurFlQSvI7nRVeXvbfdw9/macOS-27--Community-`.
Re-pull this file (see SKILL.md's "Keeping this current") if Apple ships an
update — kit was last updated 2026-07-24 at the time of this pull.

## Liquid Glass material recipe (`Kit` collection → `Liquid Glass` group, 11 vars)

These are the actual sliders behind `.glassEffect()`'s rendering — useful as
a reference recipe even where SwiftUI's API doesn't expose the same knobs
directly (see SKILL.md for how these map onto what Atelier can actually set).

| Token | Value | Notes |
|---|---|---|
| Light Angle | 0 | degrees; specular highlight direction |
| Opacity | 25 | out of 100 |
| Refraction | 70 | out of 100 |
| Depth – Regular | 30 | small controls (buttons, tab indicators) |
| Depth – Medium and Large | 30 | panels/sheets |
| Dispersion | 20 | chromatic-aberration-style edge fringing |
| Frost – Regular | 6 | blur radius, small controls |
| Frost – Medium | 16 | blur radius, medium surfaces |
| Frost – Large | 16 | blur radius, large surfaces (sheets/panels) |
| Splay – Regular | 20 | small controls |
| Splay – Medium and Large | 20 | panels/sheets |

Depth and Splay don't vary between Medium and Large — Regular (controls) is
the only tier that's tuned differently from everything bigger.

## Corner radii (`Sizes` collection → `Global` group)

| Size | Radius | Height | Font Size |
|---|---|---|---|
| Mini | 4 | 16 | 10 |
| Small | 5 | 20 | 11 |
| Medium | 6 | 24 | 13 |

This is *control*-level radius (buttons, fields, etc.), not window/panel/
sheet radius — the kit doesn't expose a window-chrome radius as a variable;
Apple's own guidance is that window/panel corners follow the display's
physical corner radius (`NSScreen` corner APIs), which is what
`NotchGeometry` already does for Atelier's own panel — don't hardcode a
value pulled from here for that.

## Context mode (`Context` collection, 1 var)

A single `Mode` string variable: **Content Area** vs **Over-glass**. This is
a semantic switch the kit's components use to decide their own contrast/
treatment depending on whether they're drawn over a Liquid Glass surface or
a flat one — conceptually the same distinction ADR 0023 (Atelier's own glass
work) hand-built as "glassIntensity as a dimming layer." Worth citing in that
ADR as confirmation Apple's own kit treats it as a first-class mode, not an
edge case.

## Color system (`Colors` collection, 63 vars, light/dark pairs)

Semantic, not literal — pull the live values from the file rather than
hardcoding a snapshot here if precision matters (some may drift release to
release). Groups: `Window Background`, `Accents` (12, e.g. Blue `#0088FF`
light / `#0091FF` dark), `Accents – Vibrant`, `Grays`, `Fills – Opaque`,
`Fills – Vibrant`, `Labels`, `Labels – Vibrant`, `Miscellaneous` (Alerts,
Progress Bars, Sidebar, Tables, Tooltips).

`Window Background`: `#FFFFFF` light / `#1E1E1E` dark.
