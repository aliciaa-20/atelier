# ADR 0006 — Built-in display brightness uses the private `DisplayServices` API

- **Status:** Accepted
- **Date:** 2026-09-07

## Context

Phase 8's volume/brightness HUD replacement needs to both *read* and *set* the
built-in panel's brightness in response to the physical function keys.

Apple's public brightness APIs (`DDCBrightness`/`DisplayServices`-adjacent
frameworks documented for third-party use) only cover **external displays**
over DDC/CI — checked during Phase 8 design, per this project's
`check-reference-apps-first` convention, before accepting the private-API
route. There is no public, documented way to read or set the built-in
panel's brightness from a third-party process.

monuk7735/mew-notch (read via `gh api` before designing — see the Phase 8
design spec) ships exactly this today, via `Brightness.m`'s
`extern int DisplayServicesGetBrightness(...)` / `DisplayServicesSetBrightness(...)`
declarations — undocumented, private-framework symbols with no Apple
stability guarantee across macOS versions. Same risk category as
[ADR 0001](0001-mediaremote-unavailable.md)'s `MediaRemote` rejection,
except this one actually works today and is not (yet) gated behind an
entitlement check the way `mediaremoted` now is.

TheBoredTeam/boring.notch takes a different, heavier path for its
`BrightnessManager`/`KeyboardBacklightManager`: a privileged XPC helper tool
(`SMJobBless`/`SMAppService`-registered daemon) rather than calling
`DisplayServices` in-process. That infrastructure is real overhead this
phase doesn't need for *screen* brightness — mew-notch proves the
unprivileged, in-process call works fine for that. (Keyboard backlight
specifically does need elevated privilege, which is exactly why Phase 8
defers it — see the design spec's non-goals.)

## Options considered

### 1. `DisplayServicesGetBrightness`/`SetBrightness` via `dlopen`/`dlsym` — **chosen**

Resolve the two symbols at runtime from
`/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices`
rather than linking the private framework directly in the Xcode project.

- No bridging header or project build-setting changes needed — the whole
  thing lives in `BrightnessSource.swift`.
- A future macOS renaming or removing the symbols degrades to `dlsym`
  returning `nil`, not a build failure or a crash.
- Costs: same private-API instability risk as mew-notch itself accepts.
  Single-machine, private-repo project (per this project's `CLAUDE.md`) — a
  broken symbol after an OS update is a "notice and fix" problem, not a
  shipped-product regression affecting other users.

### 2. Link `DisplayServices.framework` directly and declare `extern` symbols

Equivalent capability, but ties the symbol resolution to build/link time
instead of runtime, and needs an explicit "link this private framework"
project setting that's easy to lose track of later. `dlopen`/`dlsym`
achieves the same result with the failure mode entirely inside one file.

### 3. Privileged XPC helper tool (boring.notch's approach)

Correct answer for keyboard backlight (which genuinely requires elevated
privilege), but pure overhead for screen brightness, which doesn't. Deferred
to whichever future phase takes on keyboard backlight — see the Phase 8
design spec's non-goals.

## Decision

Ship option 1, resolved lazily via `dlopen`/`dlsym` in `BrightnessSource`,
with **fail-open** behavior: if either symbol fails to resolve, or a call
reports a non-zero result, `BrightnessSource.step(by:)` returns `false`.
`MediaKeyInterceptor` reads that as "could not apply the change" and lets
the key event pass through untouched (`MediaKeyMapping.shouldSuppressEvent`)
— the stock brightness HUD reappears rather than the key silently doing
nothing.

## Consequences

- A future macOS release could break these symbols with no warning. When it
  happens: re-check mew-notch/boring.notch for how they adapted (this
  project's existing `check-reference-apps-first` convention), since either
  will likely have already hit and fixed it.
- Because of the fail-open design, that breakage degrades gracefully to
  "brightness keys behave exactly like stock macOS again" rather than a
  silent dead key or a crash.
- Keyboard backlight remains out of scope for this phase specifically
  because it cannot reuse this same in-process approach.
