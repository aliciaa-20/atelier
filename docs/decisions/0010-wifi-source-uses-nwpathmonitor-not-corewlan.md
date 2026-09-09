# ADR 0010 — Wi-Fi toast uses NWPathMonitor, not CoreWLAN

- **Status:** Accepted
- **Date:** 2026-09-09

## Context

Phase 10 needed a Wi-Fi connect/disconnect toast, built on the Phase 6
`LiveActivitySource` architecture. The first design, adapted from
jackson-storm/dynamicnotch's `WifiMonitor.swift` (read via `gh api`, see
check-reference-apps-first), used `CWWiFiClient`/`CWEventDelegate` to watch
`ssidDidChange`/`powerDidChange` and read the connected network's name.

## Investigation

Two independent problems, both confirmed on-device:

1. **Crash on every toggle.** `WiFiSource.ssidDidChangeForWiFiInterface(withName:)`
   crashed the process (`EXC_BREAKPOINT` in `_dispatch_assert_queue_fail`,
   confirmed via `~/Library/Logs/DiagnosticReports`) every time Wi-Fi was
   toggled. Root cause: this project compiles with
   `-default-isolation=MainActor` (Swift 6 approachable concurrency), so
   the `@objc` `CWEventDelegate` methods were implicitly MainActor-isolated
   — but CoreWLAN invokes them directly from its own background dispatch
   queue, and the runtime executor-mismatch check fires before the
   `DispatchQueue.main.async` hop inside the method body even runs.
   `BatterySource`'s comparable C-callback avoids this because its
   run-loop source is added to the *main* run loop; an `@objc` protocol
   method invoked directly by a system framework has no such guarantee.
2. **`CWInterface.ssid()` always returned `nil`**, even after the crash was
   fixed (marking the delegate methods `nonisolated`). Confirmed via
   on-device logging across multiple real toggles. Since macOS 10.15,
   reading the Wi-Fi SSID requires Location Services authorization
   (`NSLocationWhenInUseUsageDescription` + an actual `CLLocationManager`
   authorization grant) — Atelier's `Info.plist` has neither, and adding
   that permission was explicitly declined (see the decision below).

## Decision

Replaced `CWWiFiClient`/`CWEventDelegate` entirely with `NWPathMonitor(requiredInterfaceType: .wifi)`.
Its `pathUpdateHandler` is a plain closure, not an isolated `@objc` method,
so the same executor-mismatch crash can't happen, and it needs no special
authorization — at the cost of connectivity-only detection, no network
name. Given a choice between adding a new user-facing permission grant
(Location Services, on top of the existing Automation/Accessibility asks)
just to show a network name in a 4-second toast, or dropping the name and
staying permission-free, the network name was dropped.

## Consequences

- `WiFiActivityState`/`WiFiActivityContent` carry `.connected`/
  `.disconnected` only, no associated network name.
- If a future session wants the SSID back, it needs a full
  `AccessibilityPermission`-style permission-request flow for Location
  Services first — not a small addition.
- Confirmed on-device: toggling Wi-Fi off/on no longer crashes and
  produces the expected toast.
