---
name: macos27-design-tokens
description: Pull and apply real macOS 27 design tokens (corner radii, Liquid Glass opacity/blur/refraction, color system) from Apple's official Figma UI kit, instead of guessing pixel values. Use when tuning Liquid Glass materials (ADR 0023, NotchRootView's glassPanelBackground), setting corner radii, or making any layout/visual decision that should match macOS 27 rather than an earlier OS's conventions.
allowed-tools: [Read, mcp__plugin_design_figma__get_design_context, mcp__plugin_design_figma__get_variable_defs, mcp__plugin_design_figma__get_metadata, mcp__plugin_design_figma__get_screenshot, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__tabs_context_mcp]
last_verified: 2026-09-28
source_file: https://www.figma.com/community/file/1651309434229735362/macos-27
---

# macOS 27 design tokens

Apple publishes an official macOS 27 UI Kit on Figma Community
(`#liquid-glass`, verified Apple / Figma Partner account). `tokens.md` in
this skill's own directory has the values already pulled from it — read
that first before reaching for the browser or the Figma MCP tools below.
Only go back to the live file when `tokens.md` doesn't have what's needed,
or when it's stale enough to be worth re-pulling (see "Keeping this
current").

## When to use this

- Tuning any Liquid Glass value in Atelier — `NotchRootView.swift`'s
  `glassPanelBackground`, `AtelierSettings.glassIntensity`, or anything
  touching ADR 0023's hand-built dimming/rim overlay.
- Picking a corner radius for a new control, sheet, or panel.
- Any "make it feel more iOS/macOS-like" request — pair this with the
  `apple-design` skill (motion/spacing/typography principles) and
  `ui-review-tahoe` (the review checklist); this skill is the one that
  supplies actual numbers instead of eyeballing them.
- Reviewing whether an existing value (e.g. ADR 0023's `glassIntensity`
  opacity) is in the right neighborhood as Apple's own kit.

## What Atelier can and can't take directly from this

SwiftUI's `.glassEffect()` API does **not** expose Refraction, Dispersion,
Frost, or Splay as tunable parameters — those are Apple's own internal
recipe, not knobs `.glassEffect(.regular)` hands you. Treat `tokens.md`'s
Liquid Glass section as a *reference point* for judging whether Atelier's
hand-built approximation (ADR 0023 — `.opacity()` as a dimming layer, a rim
overlay) is in the right ballpark, not as literal values to plug in:

- Opacity 25/100 is a useful sanity check against
  `AtelierSettings.glassIntensity`'s range.
- The Content Area vs Over-glass mode split in `tokens.md` is worth citing
  directly in ADR 0023 — it's confirmation Apple's own kit treats
  content-over-glass contrast as a first-class mode, the same shape as
  Atelier's dimming-layer approach, not a workaround unique to this app.
- Corner radii (`tokens.md`'s Global group: Mini 4 / Small 5 / Medium 6) are
  *control*-level, safe to use directly for buttons/fields/chips. They are
  **not** window/panel radii — Atelier's panel radius must keep coming from
  `NotchGeometry`'s measured screen-corner APIs (Invariant: panel matches
  the physical notch), never a value copied from here.

## Keeping this current

The kit's own "Updated" date is on the Community page (July 24, 2026 as of
this pull). If a value here seems stale or wrong for a real on-device
comparison:

1. Open `source_file` (the Community link, in this frontmatter) in the
   browser.
2. Click **Open in Figma → Make a copy of this file** — the Community
   preview only exposes the Cover page to `get_metadata`/`get_variable_defs`;
   Assets/Variables only resolve once it's your own file.
3. In the copy, open the **Variables** panel (left sidebar) and read the
   `Colors` / `Kit` / `Sizes` / `Context` collections directly — this is
   more reliable right now than the Figma MCP tools, which only returned
   the Cover page's metadata even against the duplicated file (a Figma
   Partner library API-access restriction, not a bug in the pull method).
4. Update `tokens.md` with what changed and bump `last_verified` above.
