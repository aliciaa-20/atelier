---
name: check-reference-apps-first
description: Use when about to implement or debug any notch-app feature in Atelier — window/panel behavior, hover/peek mechanics, now-playing polling, artwork loading, transport controls, file shelf, settings/launch-at-login, Automation-permission UX, menu bar behavior — before designing it from first principles.
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

**A second instance, worth naming explicitly because it repeated the same
mistake in a different shape:** the v2 feature pass built a real-time audio
visualizer, a scrolling-title component, and an expanded-player layout each
by hand-coding a first attempt, hitting a real bug or a "doesn't match"
rejection, and only *then* pulling reference source to fix it — instead of
checking first. Every one of those reference lookups, once actually done,
either fixed the bug in one shot (Ebullioscopic/Atoll's `AudioTap.swift` for
the CoreAudio Process Tap API) or revealed the manual approach was solving
the wrong problem entirely (jackson-storm/dynamicnotch's own "equalizer"
turned out to be a fake `isPlaying`-driven animation, not real audio — the
same technique a from-scratch first attempt would have reasonably tried,
except *this* reference confirmed it was the right call instead of a guess).
Checking references is cheap; each round of build-fail-then-check cost a
full iteration that checking first would have skipped.

This isn't only about window/panel plumbing. The same apps have already
shipped working versions of most features on Atelier's roadmap — artwork
fetch/caching, transport-control wiring, file-shelf drag & drop, a Settings
window, launch-at-login, Automation-permission UX. Before designing any of
those from scratch, check how an already-shipped app did it.

## When to Use

Before writing or debugging any code touching:
- `NSPanel`/`NSWindow` subclassing, style masks, `canBecomeKey`/`canBecomeMain`
- `acceptsFirstMouse`, click-through, hit-testing (`.allowsHitTesting`)
- Window level, `isFloatingPanel`, `hidesOnDeactivate`, activation behavior
- Notch shape/geometry math
- Hover tracking (`NSTrackingArea`) or peek/expand/collapse mechanics
- Now-playing polling, AppleScript scripting patterns for media apps
- Artwork fetching/caching, and placeholder/failure states for it
- Transport control wiring (play/pause/next/previous, seek) end to end
- File-shelf drag & drop
- A Settings window, launch-at-login (`SMAppService`)
- Automation-permission (TCC) UX — detecting denial, prompting, re-checking
- Menu bar (`NSStatusItem`) behavior and quirks

Not needed for: pure logic in `NotchGeometry`/`NotchState` (already covered
by unit tests, not reference-app territory), Spotify-specific parsing
(that's `docs/decisions/0002-*` territory), and visual styling choices with
no behavioral counterpart to check (colors, fonts, spacing).

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

1. **Name the feature or behavior you're about to build or debug** in one
   sentence ("why doesn't this button respond to a first click on a
   nonactivating panel?", "how should artwork loading degrade when the URL
   fetch fails?", "how does launch-at-login get wired to a Settings toggle?").
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
- "I'll build a first version and check references if it doesn't work" —
  this is the failure mode itself, not a mitigation. Check first; a
  reference lookup costs one `gh api` call, a wrong-guess-then-fix costs a
  full build/test/relaunch cycle, sometimes several.

## Common Mistakes

- Trusting memory of "how NSPanel usually works" instead of pulling actual
  source — AppKit has enough undocumented interaction between flags
  (`.nonactivatingPanel`, `canBecomeKey`, `acceptsFirstMouse`) that memory
  is unreliable.
- Stopping at the first reference app checked when it doesn't show the
  pattern — boring.notch and Atoll diverge in places; check more than one
  before concluding "the references don't cover this."
