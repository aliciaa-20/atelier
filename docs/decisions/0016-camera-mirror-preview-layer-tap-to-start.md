# ADR 0016 — camera mirror: preview layer, tap to start, opt-in hold-open

- **Status:** Accepted (built; on-device verification pending)
- **Date:** 2026-09-24

## Context

Phase 14 adds a Camera tab that shows a live, mirrored self-view. It is
Atelier's first use of the camera (a TCC permission and the green indicator
light), so the choices that affect battery and privacy are recorded here.

## Decision

- **Preview mechanism:** `AVCaptureVideoPreviewLayer` hosted in an
  `NSViewRepresentable`. The system composites frames on the GPU, so there is
  no per-frame CPU work; mirroring is one flag on the layer's connection.
  Session preset `.medium` (the preview is ~270pt wide). *Rejected:*
  `AVCaptureVideoDataOutput` -> `CGImage` (per-frame cost, only worthwhile for
  effects we don't want yet) and copying boring.notch's singleton
  `WebcamManager` (its auth-state and device-availability ideas were borrowed,
  its shape was not).
- **Tap to start:** opening the tab never turns the camera on. A tap does, and
  the first tap is where the permission prompt appears. This keeps the
  indicator light from flashing while swiping through tabs. Matches
  boring.notch.
- **Stop rules:** the session stops on tap-off, tab change, notch leaving
  `.expanded`, view disappearing, and app resign. `CameraMirrorSource` uses a
  generation counter so a slow `startRunning` that finishes after a stop
  shuts itself down instead of leaving the camera on.
- **Hold-open is opt-in** (`cameraHoldOpen`, default off). Only hover-out is
  suppressed, via the pure `CameraHoldOpen.shouldSuppressRetract`;
  `NotchStateMachine` is unchanged (Invariant 1). When the mirror stops while
  the pointer is outside, `NotchRootView` performs the retract the suppressed
  hover-out skipped. In hold-open mode, tapping the mirror off also closes
  the notch immediately (only that tap, not a tab change). Swipe-close and tab changes always close/stop.
- **No entitlement:** the app is not sandboxed and hardened runtime is off, so
  only `NSCameraUsageDescription` is needed.

## Consequences

- The capture path, permission prompt, denied and no-camera states are
  manual-verification only, like `System/*.swift`. Only `NotchPage.camera`'s
  transitions and `CameraHoldOpen` are unit tested.
- If the app is ever sandboxed or hardened, add the camera entitlement
  (`com.apple.security.device.camera`).
- No hold-open timeout in v1: forgetting leaves the camera on until the next
  tap, tab change or app resign.
