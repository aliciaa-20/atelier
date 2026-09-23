# Keep awake with lid closed — design

**Status:** approved to build, spec-only — not yet implemented. Parked
until a future session; safe to pick up cold from this document.

## Goal

Let the Mac keep running (coding agents, builds, downloads) with the lid
closed, without an external display. User-requested; the motivating case
is Claude Code / other agent sessions continuing unattended overnight.

Manual menu-bar toggle only (no automatic trigger) — confirmed with the
user. Primary expected use is plugged into power, but the design (battery
floor, Low Power Mode auto-off) makes on-battery use safe enough not to
need a separate code path forbidding it.

## Why this needed its own spec instead of a quick toggle

Ordinary power assertions (`IOPMAssertionCreateWithName`, what
`caffeinate` uses) do **not** override a physical lid-close sleep event —
confirmed via reference-app source, not assumed. The only real mechanism
is `sudo pmset -a disablesleep 1` (undocumented but real; sets
`SleepDisabled=Yes` in IORegistry, blocks idle + lid-close sleep, works on
battery, no external display needed).

That needs root on every toggle. A GUI app can't prompt for a password
each time, so the standard approach (used by the reference app below, and
functionally by Amphetamine) is a **one-time admin authorization that
installs a narrowly-scoped, passwordless sudoers grant** for that exact
command. This is the first thing in Atelier that *writes* a privilege
grant to the machine rather than reading state or calling a public,
unprivileged API — a materially different trust/risk shape than every
other feature shipped so far, and the reason this got a design pass
instead of going straight to code.

The user has explicitly flagged that Atelier could eventually have other
users, which raises the bar beyond "safe on my one machine": consent UX
and a real revoke path are required, not optional polish.

## Reference apps

Per `check-reference-apps-first` — one directly relevant, pulled in full.

- [**Aboudjem/Sleepless**](https://github.com/Aboudjem/Sleepless) (MIT,
  open-source) — pulled `App.swift` in full. Confirmed the
  `pmset -a disablesleep` mechanism, the one-time-authorization +
  scoped-sudoers-grant pattern (installed via `osascript ... with
  administrator privileges` running a bundled `grant.sh`), and three
  safety nets worth carrying over: an in-memory auto-off timer (dies on
  quit, never survives reboot), a user-adjustable battery-floor cutoff
  that always wins even over a deliberate turn-on, and a Low-Power-Mode
  auto-off (unless the user just deliberately turned it on this session).
  Also confirmed: `SleepDisabled` always resets to 0 on reboot regardless
  of the sudoers grant — the privileged *grant* is the only thing that
  persists, never the sleep-disabled *state*.
- Amphetamine and "Never Sleep, Even Lid Closed" (both closed-source App
  Store apps) — checked for product-level behavior only, not source; no
  new technical detail beyond what Sleepless's source already confirmed.

## Architecture

New file: `Atelier/System/SleepPreventer.swift` — same category as
`MediaKeyInterceptor`/`AccessibilityPermission`: manual-verification-only,
not unit-tested (it shells out to `pmset`/`sudo`, nothing pure to test).

Responsibilities, mirroring Sleepless's proven shape:
- **Read current state** (no root needed): parse `pmset -g` for
  `SleepDisabled`.
- **Toggle** (needs the grant): `sudo -n pmset -a disablesleep [0|1]`,
  reading the *real* exit status to distinguish "grant missing" from "ran
  and a safety net immediately reversed it" — conflating those two is
  what caused Sleepless's own early-release bug (spurious re-prompting).
- **Safety nets**, evaluated on the same poll tick as `AccessibilityPermission`-
  style state checks: battery-floor cutoff, Low Power Mode auto-off,
  auto-off timer.
- **Grant lifecycle**: install (one-time, explicit consent screen ->
  system auth sheet -> scoped sudoers write) and **revoke** (menu-bar
  action + fires on app quit-forever/uninstall, not just on toggle-off).

UI: a toggle in the existing menu-bar Behavior section (same surface as
the Liquid Glass toggle from Phase 18), not a new dedicated tab — this is
an ambient system setting, not a notch-visible Live Activity.

## Consent and revoke (the multi-user-safety requirements)

1. **Before the system auth sheet fires**, Atelier shows its own plain-
   language screen: exactly what's being granted ("lets Atelier run one
   specific command, `pmset -a disablesleep`, without asking again"), why,
   and that it can be revoked anytime from the same menu. Never let the
   OS's generic admin-password dialog be the first thing the user sees.
2. **The sudoers line pins the exact literal invocation** — full path
   (`/usr/bin/pmset -a disablesleep 1` and the `0` variant), never a
   wildcard or a bare-binary allow. Can't be silently broadened later
   without a fresh authorization.
3. **A real revoke path**: a menu-bar action that removes the sudoers
   drop-in cleanly (mirrors Sleepless's `uninstall.sh`), reachable
   without needing to find a Terminal. Also wired to fire on "quit
   forever" / app removal if Atelier gains an uninstall flow later.
4. **The sleep-disabled state itself is never persisted by Atelier** —
   only the grant is. Consistent with Sleepless: a reboot always returns
   the Mac to normal sleep behavior even if the grant is still installed.

## Safety nets (carried over from Sleepless, all in-memory / no daemon)

- Auto-off timer (e.g. 1h/2h presets) — one-shot, dies on quit.
- Battery-floor cutoff (user-adjustable, default ~15%) — always wins, even
  over a deliberate manual turn-on.
- Low Power Mode auto-off — unless the user just deliberately turned the
  toggle on this session (avoids fighting the user's own explicit intent).
- Launch-at-login (if ever added) must read true system state on launch,
  never assume/re-enable disablesleep on its own.

## Open questions for whoever picks this up

- Exact copy for the consent screen (needs a `design:ux-copy` pass or
  equivalent before shipping, not decided here).
- Whether the revoke action should also live in a general "reset Atelier
  permissions" flow if one gets built later (Accessibility, Automation,
  and this would all fit the same shape).
- Battery-floor default and auto-off timer presets — Sleepless's defaults
  (15% floor, 1h/2h) are a reasonable starting point, not user-confirmed
  for Atelier specifically.

## Testing

Manual-verification only, like the rest of `System/*.swift` — no unit
test surface here (it's all subprocess calls and OS state). Verify on
real hardware: grant install flow, toggle on/off, lid-close-with-toggle-on
actually stays awake, battery-floor cutoff actually fires, revoke actually
removes the sudoers file, and a reboot always returns to normal sleep
regardless of grant state.
