# ADR 0017 — System Monitor memory: the OS's free-memory %, not summed page counts

- **Status:** Accepted
- **Date:** 2026-09-24

## Context

The System Monitor's memory ring sat at 98-99% (solid red, "Overloaded --
Memory is almost full") on an 8 GB M3 that `memory_pressure` reported as
**46% free**. `SystemMonitorMath.memoryUsedPercent` summed
`active + inactive + wired + compressor` pages against free pages. Inactive
pages are largely cache the OS reclaims on demand, and the compressor holds
pages that are cheap to keep, so on macOS almost every machine reads 90%+.
The ring was technically "true" and practically a false alarm.

## Decision

Memory used % = `100 - kern.memorystatus_level`, the same number
`memory_pressure` prints as "System-wide memory free percentage". One
`sysctlbyname` call; the raw Mach `vm_statistics64` read and the
`MemorySample` type were removed. The pure function
`memoryUsedPercent(freePercentage:)` stays unit-tested (clamps out-of-range
readings). Severity thresholds (70% busy / 90% overloaded of *used*) are
unchanged.

*Rejected:* subtracting inactive/file-backed/purgeable pages by hand (closer
to Activity Monitor's "Memory Used", but needs more fields and is still our
own approximation); reading `kern.memorystatus_vm_pressure_level` (honest, but
only three coarse levels, so it can't drive a percentage ring).

## Consequences

- `kern.memorystatus_level` is a real, widely used sysctl but not formally
  documented API; if it ever disappears the memory ring would read nothing.
  Acceptable for a personal, unsandboxed app.
- Thresholds are unverified under genuine memory pressure. Check on-device
  under load and retune if "Busy"/"Overloaded" fire too late or too early.

## Lesson

Verify any system metric against the OS's own tool (`memory_pressure`,
Activity Monitor) before trusting hand-rolled math, and never attach an
alarming word to a number you haven't sanity-checked. A screenshot review
caught this; the code review and the unit tests did not.
