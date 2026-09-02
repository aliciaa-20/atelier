---
name: check-reference-apps-first
description: Use when about to write or debug AppKit/SwiftUI window, panel, or notch-geometry code in Atelier — NSPanel behavior, canBecomeKey/canBecomeMain, acceptsFirstMouse, hit-testing, click-through, hover tracking, window level, or notch shape/geometry — before reasoning about it from first principles.
---

# Check Reference Apps First

## Overview

Atelier is not the first app to build a notch overlay. Several open-source
macOS apps have already hit and solved the exact AppKit trivia this project
keeps running into — nonactivating-panel focus quirks, click handling,
notch geometry, hover mechanics, now-playing polling. Reasoning about these
from first principles burns iterations rediscovering things that are one
`gh api` call away.

**Concrete cost of skipping this:** ADR 0003 (`docs/decisions/0003-notch-panel-can-become-key.md`)
records a real instance — a full debugging session on `canBecomeKey`/
`acceptsFirstMouse`/click-through that Atoll's `FirstMouseHostingView` had
already solved. The fix came from reading Atoll's source, not from further
manual trial and error.

## When to Use

Before writing or debugging any code touching:
- `NSPanel`/`NSWindow` subclassing, style masks, `canBecomeKey`/`canBecomeMain`
- `acceptsFirstMouse`, click-through, hit-testing (`.allowsHitTesting`)
- Window level, `isFloatingPanel`, `hidesOnDeactivate`, activation behavior
- Notch shape/geometry math
- Hover tracking (`NSTrackingArea`) or peek/expand/collapse mechanics
- Now-playing polling, AppleScript scripting patterns for media apps

Not needed for: SwiftUI layout/styling with no window-level behavior, pure
logic in `NotchGeometry`/`NotchState` (already covered by unit tests, not
AppKit trivia), Spotify-specific parsing (that's `docs/decisions/0002-*`
territory, not a window-behavior question).

## The Reference Set

Check these, roughly in this order of relevance to Atelier's stack:

| Repo | Relevant for |
|---|---|
| [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) | Notch shape, hover/expand, now-playing UI, media controls, file-shelf drag & drop |
| [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) | `NSPanel` focus/click quirks (`FirstMouseHostingView`), `mediaremote-adapter` bridge |
| [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | Original notch-shape algorithm |
| [jackson-storm/dynamicnotch](https://github.com/jackson-storm/dynamicnotch) | AppKit+SwiftUI window/event handling, Now Playing live activity |
| [fr0sty1122/notchify](https://github.com/fr0sty1122/notchify) | Media controls, browser audio detection, file shelf |
| [navtoj/NotchBar](https://github.com/navtoj/NotchBar) | Notch-as-menu-bar-extension mechanics |
| [monuk7735/mew-notch](https://github.com/monuk7735/mew-notch) | Alternative notch-geometry/hover implementation |
| [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) | File-shelf drag & drop (backlog item) |
| [omerates760/AgentPulse](https://github.com/omerates760/AgentPulse) | Alternative notch app structure |
| [Clayton630/QuartzNotch](https://github.com/Clayton630/QuartzNotch) | boring.notch fork taken further — divergent takes on the same mechanics |
| [coaxel2/NotchIA](https://github.com/coaxel2/NotchIA) | Media player + shelf + focus + clipboard in one notch cockpit, on-device Apple Intelligence integration |

This list also lives in the root `CLAUDE.md` — update both if you add a repo.

## Procedure

1. **Name the AppKit/SwiftUI behavior you're unsure about** in one sentence
   ("why doesn't this button respond to a first click on a nonactivating panel?").
2. **Search the reference repos for it before writing code or guessing.**
   Use `gh api` to pull real source rather than trusting memory or a
   screenshot — same approach used to obtain `NotchShape.swift` and
   `ClickThroughHostingView.swift`:
   ```sh
   gh api repos/Ebullioscopic/Atoll/contents/PATH/TO/File.swift \
     --jq '.content' | base64 -d
   ```
   Find the path first with `gh api search/code` or by browsing
   `gh api repos/OWNER/REPO/git/trees/main?recursive=true`.
3. **Read how they solved it**, not just the answer — the surrounding
   context (why `.nonactivatingPanel` alone isn't enough, what
   `isFloatingPanel` is doing) usually matters for adapting it correctly.
4. **Adapt with attribution.** A short comment crediting the source repo,
   as already done in `ClickThroughHostingView.swift`. Don't copy wholesale
   without understanding it — Atelier's constraints (Invariants in
   `CLAUDE.md`) may require a different combination of flags than the
   source app used.
5. **If none of the reference apps show this pattern**, say so explicitly
   before falling back to first-principles reasoning or Apple docs — that's
   a real signal the problem might be Atelier-specific.

## Red Flags — you're about to skip this

- "This is probably a simple property I can just set" (that's what
  `canBecomeKey = false` looked like too)
- Writing more than ~10 lines of new window/panel/hit-testing code without
  having checked a reference repo first
- Debugging the same click/focus/hit-testing symptom for more than one
  iteration without having pulled reference source

## Common Mistakes

- Trusting memory of "how NSPanel usually works" instead of pulling actual
  source — AppKit has enough undocumented interaction between flags
  (`.nonactivatingPanel`, `canBecomeKey`, `acceptsFirstMouse`) that memory
  is unreliable.
- Stopping at the first reference app checked when it doesn't show the
  pattern — boring.notch and Atoll diverge in places; check more than one
  before concluding "the references don't cover this."
