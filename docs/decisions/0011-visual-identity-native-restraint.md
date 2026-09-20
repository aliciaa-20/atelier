# ADR 0011 — Visual identity: native restraint, not feature-maximalism

- **Status:** Accepted
- **Date:** 2026-09-20

## Context

`docs/FEATURES.md` §6 (productivity widgets — calendar/reminders, quick notes,
timers, color picker) and the rest of the backlog imply adding several more
surfaces to the notch. Before building any of them, we surveyed how the
reference apps this project already leans on (`check-reference-apps-first`)
actually handle a growing feature set, and read Apple's own stated design
intent for the real iOS Dynamic Island, since Atelier's whole premise is
being "a Dynamic-Island-style notch app."

Two camps emerged, not "one true reference app":

- **Native-restraint camp** — TheBoredTeam/boring.notch and monuk7735/mew-notch.
  Icon-only SF Symbol tab switcher in a `Capsule`, selection highlight drawn
  with a real system color (`Color(nsColor: .secondarySystemFill)`, not a
  hand-picked opacity), and new features (they already ship calendar +
  reminders) placed as a **card inside the existing Home view**
  (`NotchHomeView.swift`'s conditional `CalendarView()` beside the
  now-playing content), not as a new tab. mew-notch's own tagline: "minimal,
  beautiful, privacy-friendly."
- **Feature-maximalist camp** — Ebullioscopic/Atoll, Clayton630/QuartzNotch,
  coaxel2/NotchIA. Dozens of `Defaults`-backed settings, deep customization
  (glass style, corner radius, layout slots), and in NotchIA's case, "14
  native modules," a competitor comparison table, and a paid pricing tier.
  Useful for hard technical unlocks with no public API (this project already
  pulled the private-CGS-space technique from Atoll/QuartzNotch — see
  [ADR 0010](0010-lock-screen-private-cgs-space.md)), but their actual
  end-user UI reads as a third-party customization app, not something Apple
  built.

jackson-storm/dynamicnotch sits in between, and matters specifically because
its own stated mission is the closest match to what this project wants:
*"It completely copies the logic, animations, and behavior of a real Dynamic
Island on an iPhone... the main goal is to make the project as native as
possible, both in terms of design and interaction."* Its `NotchAnimations.swift`
is in fact already this project's own model — Atelier's `UI/NotchAnimations.swift`
was built from it during Phase 7 and has since been tuned further via
on-device feedback (dynamicnotch keeps `dampingFraction` fixed and only
varies `response` across its five presets; Atelier varies both, confirmed by
real testing that a bouncier open + more damped close read better). Motion
is not a gap. Its navigation idiom, however, is a genuine second native
pattern worth weighing: `HomePagePageIndicatorView` — small circular dots,
swipeable, one haptic per page change — the iOS Home Screen paging pattern,
distinct from boring.notch's segmented-control pattern. dynamicnotch's own
settings surface underneath (`homePageOrder`, `homePageDisabled`, indicator
size/spacing/stroke settings) is still feature-maximalist and is **not**
adopted here — only the dot-paging idiom itself.

Apple's own real Dynamic Island (from stable, documented HIG guidance):
fixed states (minimal/compact/expanded, not arbitrary sizes), content
updates within the existing silhouette, SF Symbols and system materials
throughout, and — the part most relevant here — **Live Activities are
explicitly meant to be temporary and time-sensitive, not a permanent
widget shelf.** A running timer is a Live Activity; a persistent calendar
pane is not what the real Dynamic Island does at all.

## Options considered

### 1. Feature-maximalist (Atoll/QuartzNotch/NotchIA model) — rejected

Directly conflicts with this project's own existing rules: no third-party
dependencies (rules out a `Defaults`-style settings framework), and
Invariant 7 ("collapsed state must be visually indistinguishable from the
stock notch") — a heavy customization surface pulls toward "a notable
third-party app," the opposite of that invariant's intent.

### 2. Keep the current tabbed-nav exactly as shipped

`NotchTabBar.swift` (Home/Shelf) currently uses text labels and hand-picked
`Color.white.opacity(0.05/0.15)` for its capsule and highlight. Concrete,
correctable defects, not a style preference: real system fills exist for
exactly this (`.secondarySystemFill` and friends) and would look native for
free. Rejected as-is; superseded by option 3's fix.

### 3. Hybrid — dot indicator (tap), icon language kept minimal, native-restraint placement rules — **chosen**

- Navigation: a compact dot indicator (dynamicnotch's visual idiom),
  tap-to-switch — chosen over a pure capsule-of-icons specifically per
  direct feedback that the priority is "not too cluttered," and a small
  dot row is visually lighter than an icon-filled capsule. A trackpad-swipe
  gesture over the dots was tried and dropped: its `NSEvent`-monitor/
  exclusion-zone plumbing (needed so the swipe didn't collide with the
  existing skip-track swipe) was the most likely source of a real
  regression (the panel not retracting on hover-away) found once shipped,
  and wasn't worth the risk for a feature this small. Tap-only is plain
  SwiftUI with no custom `NSEvent` handling.
- Colors/materials: replace hand-picked opacities with real system
  materials/colors wherever one exists, matching boring.notch's approach.
- Placement rule for future features (Phase 12 and beyond): **a feature is
  either a temporary, event-driven `LiveActivitySource` (pill/peek, appears
  while something is actually happening — matches Apple's real Live
  Activity model, and this project's existing Battery/Volume/Brightness/
  ScreenRecording pattern) or a glanceable card embedded in the existing
  Home tab (matches boring.notch's `CalendarView` placement) — not
  automatically a new tab or a new persistent surface.** A timer fits the
  first shape. A calendar/reminders view fits the second. Neither needs a
  third navigation destination.
- No new settings/customization surface accompanies any of this. If a
  toggle is truly needed, it goes in the existing menu-bar item.

## Decision

Ship option 3. `NotchTabBar.swift` needs a follow-up implementation pass
(not done as part of this ADR) to move from text-label capsule to the dot
idiom with system colors. Every future Phase 12+ feature gets an explicit
placement decision — pill/peek vs. Home-embedded card — before
implementation starts, per the rule above, rather than defaulting to "add a
tab."

## Consequences

- `docs/FEATURES.md`'s productivity-widgets survey (§6) should be read
  through this lens when Phase 12 is scoped: each entry needs a placement
  call, not just a feature description.
- `worktree-live-activity-architecture` (an existing unpushed branch) has
  its own ADR numbers 0010/0011 reserved locally — those will need
  renumbering against `main`'s sequence (0010 is now the lock-screen ADR,
  this is 0011) whenever that branch is opened as a PR.
- This does not block using Atoll/QuartzNotch/dynamicnotch source for a
  hard technical problem with no public API — only their settings-heavy,
  maximalist *UI* is out of scope, not their engineering.
