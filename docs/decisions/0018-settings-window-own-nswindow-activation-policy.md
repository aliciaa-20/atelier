# ADR 0018 — Settings window: our own NSWindow + activation-policy flip

## Context

Atelier is `LSUIElement` (no Dock icon), and its settings had outgrown a
menu-bar popover (truncated labels, no room for launch-at-login or
permission status). SwiftUI's `Settings` scene / `SettingsLink` is unreliable
to open and focus from an accessory app.

## Decision

`SettingsWindowController` creates a plain `NSWindow` hosting a SwiftUI
sidebar `List` beside the selected pane (grouped `Form`s, instant apply). Not
`NavigationSplitView`: it merges with the window toolbar and adds a blurred
scroll-edge band that panes scrolled under on load, hiding their first section. It
sets `NSApp.setActivationPolicy(.regular)` when shown and `.accessory` again
on close, as boring.notch and Atoll do. The window is created on open and
released on close, so nothing of it stays in memory while it's shut.

Tab order is a persisted list of page names resolved by the pure
`TabOrder.resolve`, read by `NotchTabBar.activePages`. Names, not indices, so
a page added later can't scramble a saved order. Launch at login uses
`SMAppService.mainApp` (no third-party package); its state is read live.

## Consequences

- Home is movable like any tab but can't be disabled; "always reopens on
  Home" became "reopens on the first tab in the user's order"
  (`NotchPageTransition`'s `firstPage`). An order saved before Home was
  movable doesn't mention it, so Home stays first for those.

- A Dock icon appears while Settings is open. Accepted: it's the price of a
  window that reliably takes focus.
- ⌘, works only while the menu is open; a global ⌘, would need a
  real main menu.
- A Debug run registers the DerivedData build for launch at login; stable
  signing (ROADMAP Phase 16) is the long-term fix.
- "Not asked yet" for Calendar and Location has no button in the Permissions
  pane: only Camera has a request helper; the others prompt from their own tab.
