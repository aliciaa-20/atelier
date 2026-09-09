# ADR 0011 — BluetoothSource polls + observes DNC, doesn't register for connect notifications

- **Status:** Accepted
- **Date:** 2026-09-09

## Context

`AirPodsSource` (Phase 6) used `IOBluetoothDevice.register(forConnectNotifications:)`
and was never registered in `NotchController` because that call crashes
the process 100% of the time on this machine's macOS build (documented in
`AirPodsSource`'s own doc comment and `docs/ROADMAP.md`'s Phase 6/8 notes).
Phase 10 needed general Bluetooth connect/disconnect detection anyway, and
an opportunity to also fix AirPods.

## Investigation

Adapted from jackson-storm/dynamicnotch's `BluetoothService+Lifecycle.swift`
(read via `gh api`, see check-reference-apps-first): observe
`DistributedNotificationCenter`'s `IOBluetoothDevice{Connected,Disconnected}Notification`
(system-wide, IPC-only — no `IOBluetoothRegisterForNotifications` call, so
no crash), then re-poll `IOBluetoothDevice.pairedDevices()` to find out
*which* device changed and whether it's currently `isConnected()`.

Confirmed on-device that the `DistributedNotificationCenter` notification
alone is not reliable: across a real AirPods connect/disconnect cycle, zero
`[BluetoothSource]` notification-handler log lines fired, even though the
underlying `pairedDevices()`/`isConnected()` state did update correctly
once polled directly. dynamicnotch's own `BluetoothService` doesn't rely on
the notification exclusively either — it runs a 3-second polling timer
(`startPollingForChanges`) as the actual source of truth, using the
notification only as a fast-path when it happens to fire.

Separately, `AirPodsBatteryReader`'s `batteryPercentCombined` key read back
`0` (unpopulated) on this machine's macOS build, while `batteryPercentLeft`/
`batteryPercentRight` (83/83) were correctly populated and closely matched
Control Center's own 84% — confirmed via on-device logging. A left/right-
based percent estimate was implemented, then dropped per direct request
("don't show battery, just show the name and connected") — see
`feedback_minimal_toast_text` in the memory system for the generalized
preference this reflects.

## Decision

- `BluetoothSource` (new) supersedes `AirPodsSource` (deleted) as the one
  registered Bluetooth detector: DNC observation for a fast path, plus a
  1-second polling timer (`pairedDevices()`/`isConnected()`) as the actual
  source of truth. 1s, not dynamicnotch's 3s, after confirming on-device
  that 3s reads noticeably slower than macOS's own native connect banner —
  `pairedDevices()`/`isConnected()` is a local IOKit query, not a radio
  scan, so the faster interval doesn't cost meaningfully more.
- Devices `AirPodsKind.classify` recognizes get a name-only "Connected"
  peek (`AirPodsActivityContent`, battery removed); everything else gets a
  generic name+state toast (`BluetoothAlertContent`). AirPods disconnect is
  silent (no toast), matching `AirPodsSource.deviceDisconnected`'s own
  prior behavior.
- `AirPodsBatteryReader.swift` is deleted — no remaining caller once
  battery was dropped from the content.

## Consequences

- The Phase 6/8 "AirPods is disabled, not shipped" limitation in
  `docs/ROADMAP.md` is resolved by this ADR, via a different detection
  mechanism than the one that crashed.
- **Still confirmed noticeably slower/less reliable than macOS's own
  native Bluetooth banner** — poll-based detection has an inherent latency
  floor and can miss very fast connect/disconnect cycles between polls.
  Accepted as "buggy but enough for now" per direct request; a further
  reliability/speed pass is backlog, not blocking.
