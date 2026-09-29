# ADR 0029 — Energy list reads `ri_energy_nj` from `proc_pid_rusage`

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

The System Monitor tab gets a "top energy users" list (Backlog queue #2). It
needs per-app energy without root, entitlements, private symbols or a
subprocess, and it must cost nothing while not on screen.

## Decision

Sample `proc_pid_rusage(pid, RUSAGE_INFO_V6)` and read `ri_energy_nj`, a
cumulative per-process nanojoule counter. Watts = delta energy / delta time
between two snapshots, taken every 3 s **only while the Energy view is
mounted** (`EnergySource.start()`/`stop()`, also stopped on notch collapse).
Helper processes are folded under their nearest ancestor that is an app
(`EnergyMath.owner`), so Chrome's helpers count as "Google Chrome".

Rejected: shelling out to `top -l 2 -o power` (spawns a process per sample,
~1 s+, text parsing, no per-app grouping) and CPU time as a proxy (ignores
GPU/ANE, could blame the wrong app).

## Verified on the target machine (M3, 2026-09-29)

- `proc_listallpids` returns a pid **count** (420 vs `ps -A` 421), not bytes.
- The ranking matches `top -o power`. `top`'s POWER column is an
  unnormalised score, not watts, so absolute values are not comparable.
- One fully busy core reads ~1.4 W; eight busy loops sum to ~3.3 W. The
  verdict tiers (1 / 3 / 8 W for the top app) map to roughly one busy core /
  several cores / the whole chip flat out.

## Consequences

- **Only ~65% of pids are readable** (269 of 420): root-owned processes
  such as WindowServer are denied without root. The list therefore shows apps
  the user owns; WindowServer, often `top`'s #1, never appears. Accepted:
  those aren't things the user can act on.
- Only `.regular` (Dock) apps are listed, top 3, and the "System" row is
  hidden: an earlier top-5 with daemons and agents read as cluttered.
- Bars scale against `max(top, 3 W)` (`EnergyMath.barFraction`), so an idle
  Mac shows short bars that agree with "Everyone's napping".
- A sample gap over 10 s (sleep) is discarded as a new baseline instead of
  diluting every reading to ~0.
- `ri_energy_nj` is less documented than the CPU counters; if a future macOS
  changes it, `EnergyMath` is unaffected and only `EnergySource` needs work.
