# ADR 0023 — Phase 18 rework: glass intensity dims, it doesn't fade

- **Status:** Accepted
- **Date:** 2026-09-28

## Context

Phase 18's full-panel Liquid Glass was parked on 2026-09-24 with the
complaint "it reads as transparency, not glass." Research into that
(`docs/research/liquid-glass-apple-guidance.md`, both from Apple: "Adopting
Liquid Glass" and the HIG Materials page) found the actual root cause:
`AtelierSettings.glassIntensity` (the Settings slider) was applied as a
plain `.opacity()` on the whole glass layer, corners included.

The research also surfaced that Apple's own guidance puts Liquid Glass on
the *navigation/controls layer*, never the *content layer* — "Ensure that
you clearly separate your content from navigation elements... to establish
a distinct functional layer above the content layer" — which the notch
body (a content-layer surface) violates outright. A first implementation
pass acted on that literally: full-panel glass was removed, and
`.glassEffect(.regular.interactive())` was applied instead to the tab bar's
selected-page indicator as a controls-only test case.

Alicia's direct call, after seeing that: she wants Liquid Glass on the
notch background specifically, guidance notwithstanding. This ADR is about
making that specific choice render well, not re-litigating it.

## Decision

Keep full-panel glass on `.expanded`/`.peeking`/`.shelf` (Invariant 7 still
keeps `.collapsed`/`.pill` flat black), but fix the actual rendering bug:

- The `NotchShape` glass layer (`.glassEffect(.regular, in: NotchShape(...))`)
  always renders at full material strength now — no `.opacity()` on it.
- `AtelierSettings.glassIntensity` now drives a `Color.black.opacity(glassIntensity * 0.35)`
  overlay on top of the glass, capped at Apple's own documented ceiling
  ("add a ~35% dark dimming layer if what's behind it is bright" — the HIG's
  guidance for the `.clear` variant, repurposed here since our variant is
  always `.regular`). Default lowered 0.7 → 0.25 so the material reads at
  close to full clarity out of the box; raise it only if a given wallpaper
  washes out legibility.
- Added `EnvironmentValues.glassBackgroundActive` (`DimmedText.swift`), set
  by `NotchRootView` on the outer `ZStack` (not the glass layer itself —
  environment values don't cross `ZStack` siblings, only flow to
  descendants). `dimmedText()` reads it to add a soft dark shadow
  (`.shadow(color: .black.opacity(0.5), radius: 1.5)`) instead of raising
  opacity, matching the skill's own "adaptive shadows flip small elements
  light/dark for legibility over any content" pattern — addresses the
  2026-09-24 UI review's parked "secondary text loses contrast in glass
  mode" finding without changing the plain-black look at all.
- Settings UI relabeled "Transparency" → "Dimming" to match what the slider
  actually does now.

## Rejected

- **Glass on controls, not body** (Apple's literal recommendation). Built
  and shown on-device (tab bar selected-indicator glass) before Alicia's
  override — kept as a real option for a future pass on individual
  controls, but not what ships now.
- **`.clear` variant with a full dimming layer** (the research doc's third
  option). Rejected per the same doc's own reasoning: little rich content
  actually sits behind the notch for `.clear` to show off, and `.regular`
  is the variant meant for content-heavy surfaces like this one anyway.
- **Removing the intensity slider entirely.** Considered since Apple's
  glass API has no native continuous "intensity" parameter, but the
  dimming-layer reinterpretation gives the slider a real, guidance-aligned
  job instead of removing a setting Alicia already uses.

## Consequences

- The known "top corners look faint/ghosted" symptom should be gone now
  that the material itself is never faded — needs on-device confirmation,
  not verified in this pass.
- `glassBackgroundActive` is a new environment key every `dimmedText()`
  call site now implicitly depends on; a future page that wants different
  glass-mode text treatment reads the same key rather than growing its own.
- Still open, unchanged by this ADR: the left-edge close glitch (needs a
  video) and confirming the corner fix and text-shadow legibility fix
  on-device.

## Update 2026-09-28: the real flicker bug was hover, not rendering

After the above shipped, Alicia reported the glass panel flickering while
music played. Two rounds of guessing were wrong, each corrected by an
on-device video (per the project's own established rule — frame-by-frame
video before touching an animation bug, not another guess):

1. First guess: `WaveformView`'s frequent `audioTap.levels` updates were
   re-triggering the system material on every re-render. Fix: extracted
   the glass background into its own `Equatable` `GlassPanelBackground`
   view so SwiftUI could skip rebuilding it on unrelated parent re-renders.
   Didn't fix it.
2. Second guess: `.glassEffect(.regular.interactive())`'s continuous
   hover/press tracking was re-triggering its own bounce/shimmer response
   under the waveform's repaints. Removed `.interactive()`. Didn't fix it
   either.
3. A video at finer time resolution (0.05s samples, not 0.15s) showed the
   real behavior: the panel wasn't glitching mid-render at all — it was
   genuinely, repeatedly opening and closing, each with its own real
   open/close blur transition. A hover feedback loop, not a rendering bug.
   Root cause: `.glassEffect()` inserts a real AppKit-backed material view
   where a plain SwiftUI `Shape.fill()` used to sit — exactly Invariant 4's
   documented failure mode ("transparent SwiftUI views still swallow
   clicks"), except for hover tracking instead of clicks. The glass
   background view was intercepting hover events `NotchRootView`'s own
   `.onHover` needs: hover in → expand → glass swallows the hover event →
   SwiftUI thinks the mouse left → collapse → mouse is still physically
   there → hover in again, indefinitely.
   Tried: `.allowsHitTesting(false)` on the glass background, reasoning it
   was purely decorative and should never have been hit-testable in the
   first place (same as the flat-black fill it replaces). **Did not fix
   it either** — confirmed still flickering on-device, with the naked eye,
   not just in a recording.
4. Added temporary `os_log` instrumentation (`NotchRootView`'s
   `.onHover`, `NotchGestureModifier`'s `onOpen`/`onClose`,
   `NotchController.triggerPeek`, every `viewModel.state` change) and
   watched it live via `log stream` while reproducing. This is the one
   step that produced real data instead of another theory: `.onHover`
   itself fires `hovering=true`/`hovering=false` in a genuine, tight loop
   (cycle lengths as short as ~100-150ms) — never `NotchGestureModifier`,
   never `triggerPeek`. So it is a real hover oscillation, not a peek/
   gesture misfire, ruled out directly from Console output rather than
   inferred.
   Tried: a 120ms debounce on hover-exit (`NotchRootView.hoverExitTask`),
   on the theory that `.onHover`'s hit-test region lags the actively-
   animating `frameSize` during the open/close spring. **Also did not
   fix it.** Kept in the code as a harmless defensive improvement (a
   genuine hover-out now closes ~120ms later, imperceptible), but it is
   not the fix.

**Status: unresolved, stopped per direct instruction.** Four attempts across
two categories (rendering-level, then confirmed-real hover-level) did not
fix this. The debounce not working is itself informative: it means the
"hit-test lags an animating value" theory is probably wrong or incomplete,
since debouncing the *symptom* of that race should have absorbed it even if
the mechanism were right. The `hoverDebugLog`/temporary logging was removed
before committing (kept only as a comment pointing back to this ADR); the
debounce (`hoverExitTask`) was left in.

**Lesson:** two rendering-level guesses were spent on plausible theories
before the video resolution was fine enough to show this wasn't a rendering
problem. Once real `os_log` instrumentation confirmed *which* mechanism was
actually firing, two more theory-driven fixes (hit-testing, then debounce)
still didn't land — meaning even "watch it happen live" data wasn't enough
to find the fix this session. Next attempt should probably instrument
*why* `.onHover` reports false (e.g., log the actual view bounds/mouse
location at the moment it fires) rather than continuing to theorize about
mechanisms from the outside.
