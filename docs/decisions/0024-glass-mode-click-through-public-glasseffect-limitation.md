# ADR 0024 — glass mode's click-through is a public `.glassEffect()` API limitation

- **Status:** Proposed (root cause identified; no fix implemented — see Decision)
- **Date:** 2026-09-28

## Context

Phase 18's known camera-tap bug turned out to actually be two unrelated bugs,
plus a third, more serious one surfaced during their investigation:

1. **Camera tap-to-mirror not registering.** Root-caused and fixed: SwiftUI's
   `.contentShape(Rectangle())` hit-test region tracks `frameSize`, which is
   mid-spring during open/tab-switch animations — a tap landing before the
   spring settles can miss. Same mechanism as the already-fixed glass
   hover-flicker bug (PR #44), just a second trigger. Fixed by gating page
   content's `allowsHitTesting` on a new `contentGeometryUnstable` flag,
   raised for the real duration of any state/page-changing animation via
   `withAnimation`'s `completionCriteria: .logicallyComplete` (`NotchRootView
   .animateStateChange`). Confirmed fixed on-device.
2. **Tab-switch retract-and-snap-back flicker.** Root-caused via `os_log`
   evidence: a real tab-dot *click* (not passive hovering) fires a genuine
   hover-exit ~24ms after its matching hover-enter, only ~5pt away — close
   enough to be the same click's natural cursor jitter, not a real hover-out,
   but outside PR #44's original 1pt/no-time-bound tolerance (validated only
   against a stationary hover, never a click). Widened the tolerance to 8pt
   and added an 80ms time bound. **Confirmed NOT fixed on-device** — the
   flicker persists. The real trigger is still unknown; this fix addressed
   the one captured log pattern, not necessarily the only one.
3. **Click-through to the app behind the notch** (this ADR). Reported
   independently, then confirmed via a full-resolution screen recording:
   with a normal windowed (not fullscreen) Safari sitting behind the notch
   panel, clicking/hovering the notch's own tab-bar dots shows an **I-beam
   text cursor** — meaning the OS is resolving cursor ownership from
   Safari's window, not Atelier's panel, at that screen point. Confirmed by
   the user that a genuine click there does reach Safari (a tab-bar
   interaction), not just the cursor shape.

## Investigation

Two theories were tested and ruled out before landing on the one below:

- **Fullscreen-menu-bar interaction.** `NotchPanel.swift` already documents
  a related, previously-discovered quirk (`.statusBar` level claiming
  `mouseDown` dispatch in the menu bar's screen strip, why the panel uses
  `.mainMenu + 3` instead). Ruled out: the user confirmed Safari was
  **windowed, not fullscreen**, and the click-through still happened.
- **Missing `isFloatingPanel`/`hidesOnDeactivate`.** ADR 0003 documents
  these as part of the combination (with `canBecomeKey`/`acceptsFirstMouse`)
  that fixed click handling generally, citing Atoll's `DynamicIslandWindow`.
  Checking `NotchPanel.swift` found `isFloatingPanel`/`hidesOnDeactivate`
  were **never actually applied**, despite being part of that documented
  decision — a real gap, restored as part of this investigation (see
  `NotchPanel.swift`). **Ruled out as the cause of this bug**: applying it
  did not fix the click-through. Kept anyway since it correctly restores
  ADR 0003's own decision, independent of this bug.
- **Decisive test:** does the click-through happen with glass mode off
  (flat black panel), same Safari-behind-notch setup? **No** — the user
  confirmed black mode "works perfectly fine." The bug is specific to
  `.glassEffect()`.

**Reference-app comparison** (per `check-reference-apps-first`): neither
boring.notch nor NotchIA use `.glassEffect()`/Liquid Glass at all. Atoll
does, but not via SwiftUI's public API — `DynamicIsland/helpers/
LiquidGlassBackground.swift` drops to AppKit's *private* `NSGlassEffectView`
(looked up via `NSClassFromString`, since it isn't public), then walks the
resulting `CALayer` tree for layers named `CABackdropLayer` (Apple's
real-time backdrop-sampling layer — what actually reads the screen behind
the window to render the glass material) and forcibly sets `windowServerAware
= true` and `scale = 1.0` on them via KVC, **re-applying this continuously
via KVO** whenever the system resets those properties. That KVO-reapply loop
is the tell: Apple's own backdrop layer does not reliably stay
"window-server-aware" on its own inside a custom floating panel, and a
`CABackdropLayer` that isn't `windowServerAware` is a plausible, direct
explanation for a mismatch between what's rendered (our panel, on top) and
what the window server considers to own hit-testing/cursor resolution at
that point (Safari, underneath).

SwiftUI's public `.glassEffect(_:in:)` — what `NotchRootView.GlassPanelBackground`
uses — exposes no equivalent to `windowServerAware`, `scale`, or any private
`CABackdropLayer` property. There is no supported way to patch this through
the public API Atelier currently uses.

## Decision

**No fix implemented yet.** Documenting the root cause and the real options,
since committing to a fix here is a bigger call than a normal bug patch:

1. **Adopt Atoll's private-API approach** (`NSGlassEffectView` +
   `CABackdropLayer` KVC/KVO patch). Proven to work in a real shipped notch
   app. Real cost: private API (`NSClassFromString`, `setValue(forKey:)` on
   undocumented properties) can silently break on any macOS update with no
   compiler warning, and meaningfully increases the complexity of
   `GlassPanelBackground`. No third-party dependency needed (matches
   Conventions), but this is architecturally a bigger change than adopting
   one.
2. **Restructure glass to match Apple's own usage guidance more closely.**
   The `liquid-glass` skill's Design Rules are explicit: glass is the
   *navigation layer* (bars, toolbars, floating controls), never a full
   content backdrop, and "no steady-state intersections" — content
   shouldn't rest half-under a glass element. Atelier's current
   `GlassPanelBackground` applies `.glassEffect()` as the *entire panel's*
   background, with all interactive content (tab bar, buttons) resting on
   top of it — a different shape of usage than Apple's own guidance
   describes, and plausibly a contributing factor independent of the
   `CABackdropLayer` issue. Scoping glass down to non-interactive chrome
   only would be a real visual redesign, not a quick patch, and may not
   fully eliminate the bug on its own.
3. **Leave Liquid Glass opt-in and default-off** (already true —
   `AtelierSettings.glassEffectEnabled` defaults off), document this as a
   known limitation, and don't invest further until either Apple exposes
   the needed control publicly or there's a deliberate decision to take on
   the private-API risk.

No option was implemented as part of this investigation. Revisit when
there's a deliberate choice to make among these three, not as a quick
follow-up.

## Consequences

- Camera-tap-to-mirror and the animating-hit-test-geometry class of bug are
  fixed and confirmed on-device — real progress, independent of this ADR's
  open question.
- The tab-switch retract flicker (item 2 above) is a separate, still-open
  bug with a partial, unconfirmed fix in place. Needs its own fresh evidence
  gathering, not assumed to share this ADR's root cause.
- **Glass mode has a confirmed, real click-through-to-the-app-behind bug.**
  Until one of the three options above is deliberately chosen and
  implemented, glass mode should be treated as carrying this risk any time
  another app's window sits behind the notch panel — worth surfacing this
  explicitly in ROADMAP's Phase 18 entry (glass is opt-in, but the person
  turning it on should know why it's still marked partial).
- `NotchPanel.isFloatingPanel`/`hidesOnDeactivate` are now set, correctly
  restoring ADR 0003's own decision — unrelated to this bug, but a real gap
  worth having fixed regardless.
