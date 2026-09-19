# ADR 0010 — Lock-screen widget uses a private CGS space, not a public API

- **Status:** Accepted
- **Date:** 2026-09-19

## Context

Phase 11's lock-screen now-playing card needs a window that stays visible
*after* the screen locks. macOS hides ordinary user-session windows the
instant the screen locks — there is no public, documented API for a
third-party process to draw a widget on the lock screen. `docs/FEATURES.md`
flagged this explicitly as a feasibility risk before design started, per
this project's `check-reference-apps-first` convention: "what reference
apps call 'lock screen' support is likely their own floating panel staying
drawn over the lock-screen image, not a true system-integrated widget."

Reading the actual source (not just READMEs) of Ebullioscopic/Atoll and
Clayton630/QuartzNotch confirmed exactly that: both hold an ordinary
`NSWindow` and delegate it into a private CGS ("CoreGraphics Services")
space via undocumented `SkyLight.framework` symbols
(`SLSSpaceCreate`/`SLSSpaceSetAbsoluteLevel`/window-to-space assignment),
the same family of private-framework techniques already accepted in this
project for brightness ([ADR 0006](0006-displayservices-private-api-for-brightness.md)).
Lakr233/SkyLightWindow packages the same technique as a standalone,
reusable operator.

## Options considered

### 1. Vendor and harden a `SkyLightSpaceOperator` (Lakr233/SkyLightWindow's technique) — **chosen**

Resolve the `SkyLight.framework` symbols via `dlopen`/`dlsym` (same runtime
-resolution pattern as ADR 0006, not a linked private framework), create a
space, and delegate the window into it via
`CGSSpaceSetAbsoluteLevel`/window-to-space assignment. `isAvailable` gates
every caller — a broken symbol degrades to the widget simply not appearing,
not a crash.

- Matches what Atoll and QuartzNotch actually ship today, confirmed by
  reading their source directly, not assumed from behavior.
- Same fail-open shape already established by ADR 0006: `LockScreenPanelController.updateVisibility`
  checks `SkyLightSpaceOperator.shared.isAvailable` before ever showing the
  window.
- Review during implementation caught and fixed two real gaps before they
  shipped: an unvalidated `spaceCreate` return (a `0` return — space
  creation failure — would have silently reported `isAvailable = true`
  with a broken space) and an ABI-sloppy parameter type (`Int32` where the
  real signature takes a `CFDictionaryRef`, accidentally safe only for the
  literal `0` this project passes).

### 2. Don't ship a lock-screen widget at all

The originally-flagged fallback if the spike had found no viable
technique. Rejected once the spike confirmed a working, already-shipped
approach exists.

### 3. A privileged helper / launch daemon to draw on the lock screen

No evidence any reference app needs this — the private CGS space approach
runs entirely in-process, same privilege level as the rest of Atelier.
Would add real overhead (an `SMAppService`-registered daemon, matching the
heavier path ADR 0006 rejected for brightness) for no capability gain.

## Decision

Ship option 1: `SkyLightSpaceOperator` (a single `System/`-layer type,
`isAvailable`-gated) is the sole seam between `LockScreenPanelController`
and the private API, mirroring `BrightnessSource`'s own seam around
`DisplayServices`.

## Consequences

- Same risk category as ADR 0001 and ADR 0006: an undocumented,
  Apple-unsupported API that a future macOS release could change or remove
  with no warning. Single-machine, private-repo project — a broken symbol
  is a "notice and fix" problem, not a shipped-product regression.
- When it breaks: re-check Atoll/QuartzNotch first (this project's
  standing `check-reference-apps-first` convention) — either will likely
  have already adapted.
- The lock-screen card is therefore explicitly **not** a real,
  OS-integrated lock-screen widget (no `WidgetKit` lock-screen surface
  involvement) — it's a floating window that happens to keep rendering
  over the lock screen image via a private space. That distinction matters
  if Apple ever ships a real third-party lock-screen widget API: this
  entire mechanism would likely be replaced, not extended.
