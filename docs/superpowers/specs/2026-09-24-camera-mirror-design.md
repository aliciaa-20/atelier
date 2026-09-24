# Camera mirror (Phase 14) — design

## Goal
A Camera tab in the expanded notch showing a live, mirrored self-view of the
built-in camera, for a quick "how do I look" check before a call. Success: it
feels like part of the notch (clean, minimal), and the camera is on only when
the user asked for it and is looking at it.

## Decisions (agreed with Alicia, 2026-09-24)
- **Placement:** its own tab, `NotchPage.camera` (not a toggle on Home).
- **Start:** tap to start. Opening the tab never turns the camera on.
- **Retract:** default is retract-as-normal (matches boring.notch, whose
  `WebcamView` calls `stopSession()` in `.onDisappear`). Opt-in setting
  `cameraHoldOpen` keeps the notch open while the mirror is live. No timeout in v1.
- **Preview mechanism:** `AVCaptureVideoPreviewLayer` in an `NSViewRepresentable`
  (GPU-composited, lowest CPU/battery). Session preset `.medium`. Rejected:
  `AVCaptureVideoDataOutput` -> `CGImage` (per-frame CPU cost, only useful for
  effects we don't want yet); copying boring.notch's singleton `WebcamManager`
  (borrow its auth-state and device connect/disconnect ideas only).

## UI: keep it clean
- **One frame size for every state** (placeholder, live, denied, no camera),
  sized to the page's usual content area and inset by
  `NotchLayout.pageHorizontalInset` (26). No layout jump when the state changes.
- **Live:** just the mirrored video in a rounded rect. No overlaid buttons,
  labels, or borders. Tap the preview to stop.
- **Placeholder:** one SF Symbol (`web.camera`) and one short line
  ("Tap to mirror"), low-contrast, centered.
- **Denied:** same layout, symbol + "Camera access is off" and a single
  "Open Settings" button. **No camera:** symbol + "No camera found".
- State changes crossfade (fade-only, per ADR 0014); no springs or bounces here.
- Polish, built in from the start: VoiceOver labels ("Camera mirror, off/on"),
  subtle press feedback on the tap target, reduced-motion respected.
  Run `ui-review-tahoe` after the first visual pass.

## Components
- `System/CameraPermission.swift` — thin TCC helper like `CalendarPermission`:
  live status read (never cached) + deep link to Privacy_Camera.
- `Widgets/Camera/CameraMirrorSource.swift` — owns the `AVCaptureSession`;
  `start()`/`stop()`; handles device unplug/replug. Lifetime tied to visibility
  (same principle as `AudioTap` tied to `isPlaying`).
- `UI/CameraMirrorPageView.swift` — the tab and its four states.
- `Notch/NotchPage.swift` — add `.camera`; page-transition reset to Home on
  collapse unchanged.
- `AtelierSettings` — `cameraEnabled` (default on), `cameraHoldOpen` (default
  off); menu-bar toggles for now, move into Settings window in Phase 16.
- `Info.plist` — `NSCameraUsageDescription`. No entitlement needed: app is not
  sandboxed and hardened runtime is off.

## Behavior and invariants
- Session stops when: the mirror is tapped off, the tab changes, the notch
  collapses (unless hold-open is on and the mirror is live), or the app resigns.
- Hold-open lives in `NotchViewModel`: it skips the retract while the mirror is
  live and dispatches the deferred `hoverEnded` when the mirror stops.
  `NotchStateMachine` is not changed (Invariant 1). The decision itself is a
  small pure function so it can be unit tested.
- Preview and placeholder are hit-testable only where they need to be
  (Invariant 4). Panel size is unchanged (Invariant 3).
- Battery: nothing runs unless the camera is live; no polling, no timers.

## Testing
- Unit: `NotchPage.camera` reset-to-Home on collapse; the hold-open decision
  function.
- Manual only (no real camera or TCC grant in CI): first-tap permission prompt,
  denied state, live preview + mirroring, stop on retract, hold-open on/off,
  camera unplug. Verified on-device by screenshot.

## Out of scope for v1
Filters/effects, photo capture, external camera picker, auto-start, hold-open
timeout.
