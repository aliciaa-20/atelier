# Settings window — design (ROADMAP Phase 16)

Date: 2026-09-24 · Branch: `feat/settings-window`

## Goal

Replace the crowded menu-bar settings menu with a native Settings window, and
add the things the menu can't hold: launch at login, a permission status
panel, and user-reorderable tabs. The menu-bar menu becomes slim.

Success: Alicia can open Settings with ⌘, or from the menu, change every
existing setting there, reorder/enable tabs by dragging, toggle launch at
login, and see/re-check permission status — and the notch reflects changes
without a relaunch.

## Reference research

- **Apple:** Settings window with a sidebar of panes, each a grouped `Form`;
  changes apply instantly (no Save); ⌘, opens it; menu-bar apps keep the
  menu slim.
- **boring.notch / Atoll** (`components/Settings/SettingsWindowController.swift`,
  `SettingsView.swift`): hand-built `NSWindowController` hosting a
  `NavigationSplitView`; flips `NSApp.setActivationPolicy(.regular)` while
  open and back to `.accessory` on close. They use the third-party
  `LaunchAtLogin` package; we use `SMAppService.mainApp` (no dependencies).
- The SwiftUI `Settings` scene / `SettingsLink` is unreliable in
  `LSUIElement` apps, so it is rejected (Approach B). Keeping the popover
  menu (Approach C) is the status quo being escaped.

## Decisions

1. **Own `NSWindowController` + SwiftUI `NavigationSplitView`** (Approach A).
2. **Slim menu:** `Settings…` (⌘,) and `Quit`. Nothing else.
3. **Live OS status over stored copies** for launch at login and
   permissions (they can change outside the app).
4. **Home is pinned first** in the core work. Reorderable Home is a
   planned final stage (Alicia definitely wants it), with its own small
   design pass because it touches `NotchPageTransition`, gestures, tests.

## Structure

- `Settings/SettingsWindowController.swift` — AppKit shell: singleton,
  lazily created, released on close; policy flip to `.regular` on show,
  back to `.accessory` on close.
- `Settings/SettingsView.swift` — sidebar + pane switch. One small view file
  per pane under `Settings/Panes/`.
- Panes: **General** (launch at login, peek on track change, gestures) ·
  **Appearance** (Liquid Glass toggle + intensity) · **Tabs** (enable +
  drag-reorder) · **Widgets** (Calendar options, Camera hold-open, Color
  Picker) · **Permissions**.
- State stays in `AtelierSettings` (`@AppStorage`), so window and notch
  stay in sync as today. One new key: tab order.

## Tab order

- `Notch/TabOrder.swift` — pure, Foundation-only (Invariant 1).
  `TabOrder.resolve(stored: [String], enabled: Set<NotchPage>) -> [NotchPage]`:
  1. Home always first.
  2. Enabled pages follow the stored order.
  3. Enabled pages missing from the stored list are appended in default order.
  4. Unknown names and duplicates are ignored.
- Stored as `[String]` of page names (needs `NotchPage: String`-backed
  names), so adding a page later cannot scramble a saved order. Empty
  stored value → today's order (no change on upgrade).
- Wiring: `NotchTabBar.activePages` (the single choke point for the dots and
  swipe navigation) calls `TabOrder.resolve`. Still read live, not cached.
- UI: Tabs pane is a `List` with `.onMove`; each row = icon, name, enable
  toggle; Home is a locked top row. The per-page enable toggles move here
  from the Widgets pane.

## Launch at login

`System/LaunchAtLogin.swift` wraps `SMAppService.mainApp`
(`register`/`unregister`/`status`). The toggle reads live `.status`.
`.requiresApproval` shows "Needs approval in System Settings" + a button to
open Login Items. Caveat (documented in a code comment): it registers
whichever build is running, so a Debug run registers the DerivedData copy;
stable signing (separate roadmap item) is the long-term fix.

## Permissions pane

One row per permission (Accessibility, Calendar, Camera, Location): status
dot + text, and a state-appropriate button ("Grant Access" when
undetermined, "Open System Settings" when denied). Re-checks on
`NSApplication.didBecomeActiveNotification`. If a helper lacks a clean status
accessor, add a small one rather than reshaping it. Automation (Spotify) can
only be observed by attempting, so it is a follow-up verified by hand first.

## Performance

Window exists only while open; no timers/pollers; permission re-check is
event-driven; activation policy reverts on close.

## Testing

Unit tested: `TabOrder` (empty → default order, disabled skipped, new page
appended, garbage ignored). Manual, stated plainly (like `System/*.swift`):
window open/focus, launch at login, permission rows. No extra tests beyond
these.

## Stages

1. Slim menu + window shell (`SettingsWindowController`, empty sidebar, ⌘,)
2. General + Appearance panes (move existing toggles, add launch at login)
3. Tab order: pure `TabOrder` + tests, `activePages` wiring, Tabs pane
4. Widgets + Permissions panes (incl. parked label-truncation / indent fixes)
5. Reorderable Home (own small design pass first)
6. Docs: ADR (window approach + activation-policy flip), README, FEATURES,
   ROADMAP Phase 16

Each stage builds, passes tests, and is committed; on-device screenshots
after stages 1–4.

## Out of scope

Custom menu-bar template icon, stable signing identity, Automation-permission
UX beyond a status note (all remain in ROADMAP Phase 16 / separate items).
