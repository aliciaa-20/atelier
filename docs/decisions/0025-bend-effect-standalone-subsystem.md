# ADR 0025 — desktop bend effect is a standalone subsystem, not a notch or Widgets feature

- **Status:** Accepted
- **Date:** 2026-09-28

## Context

The desktop bend effect (full port of [IuCC123/BendMac](https://github.com/IuCC123/BendMac),
MIT — see `docs/superpowers/specs/2026-09-28-bend-effect-design.md` and
`docs/superpowers/plans/2026-09-28-bend-effect-implementation.md`) is a
whole-built-in-display overlay that visibly folds and blurs the desktop as
the lid closes. Several structural questions came up while placing it in
the codebase that don't have an obvious single answer from the existing
`Notch/`/`Widgets/`/`LiveActivitySource` conventions, since this feature
has nothing to do with the notch panel at all.

## Decisions

1. **New top-level `Atelier/BendEffect/` folder, not `Notch/` or `Widgets/`.**
   It owns an entirely separate `NSPanel` (`BendEffectOverlayWindow`) with
   its own lifecycle, covering the whole built-in display -- structurally
   closer to `LockScreen/`'s "separate subsystem" shape than to anything
   that shares `NotchPanel`'s window or `NotchState`'s state machine. A
   `LiveActivitySource` conformer would imply it renders *inside* the notch
   panel, which it never does.

2. **Settings persist through `AtelierSettings`, not a private `UserDefaults`
   instance inside the controller.** BendMac's own `AppModel` reads/writes
   `UserDefaults` directly with its own `restoringPreferences` bookkeeping.
   Every other Atelier feature's settings go through the one `AtelierSettings`
   enum instead, so `BendEffectController` reads `AtelierSettings.bendEffect*`
   computed properties and `BendEffectPane` binds to the same keys via
   `@AppStorage`, matching `AppearancePane`'s existing pattern. Keeps one
   settings-persistence convention project-wide rather than a second,
   feature-local one.

3. **The Escape-to-pause hotkey is registered directly in `BendEffectController`,
   not through the existing `GlobalHotkeys` class.** `GlobalHotkeys` is
   scoped to the Teleprompter's fixed three-action, `⌃⌥`-modified key set
   (play/pause, faster, slower) with a single owned `handler` closure and
   its own hotkey signature. A bare, unmodified Escape used only transiently
   while the bend overlay is visible doesn't fit that shape -- forcing it in
   would mean either generalizing `GlobalHotkeys` well beyond what
   Teleprompter needs today or giving it a second, incompatible action
   vocabulary. `BendEffectController` instead calls Carbon's
   `RegisterEventHotKey`/`InstallEventHandler` directly, the same near-verbatim
   approach BendMac's own `AppModel` used, with its own signature (`'ATLB'`,
   distinct from `GlobalHotkeys`'s `'ATLR'`). A distinct signature alone is
   **not** sufficient, though: Carbon delivers every `kEventHotKeyPressed`
   event to the most recently installed handler first, and a handler that
   unconditionally returns `noErr` swallows the event before any
   earlier-installed handler (or vice versa) ever sees it, regardless of
   signature. Caught in code review — both handlers now read the event's
   `EventHotKeyID.signature` and return `eventNotHandledErr` for anything
   that isn't their own, letting Carbon fall through to the other handler.

4. **A menu-bar toggle was added, not just a Settings-only switch.** The
   design spec left this as an open question. Decided in favor of parity
   with the existing `Ghost Mode` toggle already in `AtelierApp`'s
   `MenuBarExtra`: both are simple on/off states for a background effect,
   and the added row costs one `Toggle` bound to the same `AtelierSettings`
   key the Settings pane already writes to. No new state, no new plumbing.

## Consequences

- `BendEffect/` can be read, tested, and reasoned about entirely on its
  own -- nothing in `Notch/` or `Widgets/` references it, and vice versa.
- A future contributor extending `GlobalHotkeys` for a different feature
  should not assume it's the only hotkey mechanism in the codebase;
  `BendEffectController`'s Escape handler is a deliberate, documented
  exception, not an oversight.
- If a second feature later wants a similarly narrow, transient global
  hotkey, this ADR is the precedent for handling it directly rather than
  overloading `GlobalHotkeys` -- but a *third* such case would be a signal
  to reconsider and build a proper general mechanism instead.
