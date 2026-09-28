# Desktop bend effect — design

**Status:** approved to build (full port), spec-only — not yet implemented.
Parked until a future session; safe to pick up cold from this document.

## Goal

Port [IuCC123/BendMac](https://github.com/IuCC123/BendMac) (MIT) into
Atelier: the desktop visibly bends and blurs as the lid closes, mirroring
the physical fold. User-requested, full faithful port (not a minimal
slice) — tunable Appearance controls (style, blur, perspective, shadow)
and Lid Behavior (follow lid vs. a manual angle, calibrate the clear
angle) are all in scope, same as the reference app.

This has nothing to do with the notch. It's a whole-built-in-display
overlay, unrelated to `NotchPanel`/`NotchState`. Structurally it's closer
to `LockScreen/` (an entirely separate `NSWindow`/lifecycle) than to
anything in `Notch/` or `Widgets/`.

## Confirmed before scoping

- **Hardware:** BendMac's own README only confirms an M5 MacBook Air.
  Probed this machine (MacBook Pro M3, Mac15,3) directly with the same
  `IOHIDManager` match criteria BendMac's `LidSensor.swift` uses
  (`kIOHIDVendorIDKey: 0x05AC, kIOHIDPrimaryUsagePageKey: 0x20,
  kIOHIDPrimaryUsageKey: 0x8A`) — the sensor exists and returned a
  plausible live angle (114°) on the first read. Confirmed working on
  this exact machine, not just assumed from their README.
- **Permission:** needs Screen & System Audio Recording (ScreenCaptureKit)
  — a materially broader grant than anything else Atelier asks for today.
  Same "this needed a design pass, not straight to code" bar as the
  keep-awake-with-lid-closed spec, for a different reason (privacy-
  sensitive capture vs. a privileged sudoers write there).

## Reference app

[IuCC123/BendMac](https://github.com/IuCC123/BendMac), MIT, pulled
directly via `gh api` (not memory/README) per `check-reference-apps-first`
— `LidSensor.swift`, `DesktopCapture.swift`, `Renderer.swift`,
`BendMath.swift`, and `Bend.metal` all read in full before writing this
spec. Credit in each ported file's header comment, same as
`ClickThroughHostingView.swift`'s existing convention.

## Architecture

New top-level folder `Atelier/BendEffect/`, mirroring `LockScreen/`'s
"separate subsystem" shape rather than living under `Notch/` or `Widgets/`:

| File | Role | Port notes |
|---|---|---|
| `BendMath.swift` | `progress(angle:clearAngle:)` (smoothstep-eased fold amount) and `smooth(current:target:dt:)` (exponential glide) | **Pure Foundation, unit-tested** — same category as `NotchGeometry`/`ScriptMatcher`. Port near-verbatim; this is the one piece of the whole feature that gets real test coverage |
| `LidSensor.swift` | `IOHIDManager`-based polling of the undocumented lid-angle HID report, three polling rates (idle/watching/active) | Port near-verbatim (already confirmed working above). Manual-verification only, like `System/*.swift` |
| `DesktopCapture.swift` | `ScreenCaptureKit` `SCStream` wrapping the built-in display, excluding Atelier's own windows, frame rate throttled to 5fps idle / 60fps while bending | Port and adapt to Swift 6 strict concurrency conventions (per the `write-swift` skill) — the reference already uses `@MainActor`-isolated state plus a capture-queue callback, should translate cleanly |
| `Bend.metal` | Vertex/fragment shader: projective fold (single homography, hinge anchored at the bottom edge), graduated defocus via four pre-blurred mip textures, edge feathering + side shadow | Port verbatim — this is the actual visual craft, no reason to rewrite the math |
| `Renderer.swift` | `MetalKit` pipeline: owns the pre-blur passes, drives the shader with live `Params` (progress/perspective/blur/shadow/style) | Port and adapt — first `MTKView`/Metal pipeline in Atelier, so this is also the first file to establish that pattern for anything that comes after it |
| `BendEffectOverlayWindow.swift` | `NSPanel` subclass covering only the built-in display, shown only while `progress > 0` | New file, not a port — Atelier's own window needs (`NotchController`'s panel-lifecycle conventions) differ enough from BendMac's `OverlayWindow` that adapting beats porting line-for-line |
| `BendEffectController.swift` | Orchestrates sensor → capture → renderer → overlay, mirroring `AppModel`'s `enable()`/`connect()`/`inputChanged()` state machine (reconnect-on-failure, capture only starts once actually bending) | Port the *state machine shape*, not the file — `AppModel.swift` mixes in Settings/menu-bar concerns Atelier keeps separate (own `Settings/Panes/*` convention) |

**Already aligned with Atelier's own performance principle** (see
CLAUDE.md's Performance section): BendMac only opens the capture stream
once the lid actually starts folding, throttles to 5fps otherwise, and the
HID sensor itself has three polling rates keyed to whether the effect is
idle/watching/active. Port that behavior as-is rather than simplifying it
away — it's already the "cheapest mechanism that still reads as smooth"
default this project asks for.

## Settings

A new Settings pane, `Settings/Panes/BendEffectPane.swift` (own pane, not
folded into Appearance — BendMac's own controls are numerous enough to
warrant it: enable toggle, style, blur, perspective, shadow, Lid Behavior
section with Follow Lid / manual angle slider / Calibrate open angle
button). Escape-to-pause and open-at-login follow existing precedent
(`GlobalHotkeys`/Carbon already used by Teleprompter; `LaunchAtLogin`
already exists).

## Permissions

New row in the Permissions pane and README's permissions table:
**Screen & System Audio Recording** — "Captures your desktop to render
the fold effect while the lid is closing. Only runs while actively
bending; nothing is recorded or saved." `capturesAudio = false` is
already set in BendMac's own `SCStreamConfiguration` — carry that over
explicitly, Atelier doesn't want system audio here at all.

## Open questions for whoever picks this up

- Exact default values for style/blur/perspective/shadow — BendMac's own
  defaults are a reasonable starting point, not confirmed for Atelier.
- Whether "Only the built-in display is affected" (BendMac's own
  constraint) is acceptable as-is, or whether multi-monitor users should
  get an explicit note in Settings.
- Icon/menu-bar surface for a manual toggle vs. the Settings-only enable
  switch — BendMac exposes both; decide whether Atelier needs a menu-bar
  entry point too or Settings alone is enough.

## Testing

`BendMath.swift` gets real unit tests (pure, deterministic — easе curve
and glide function both testable with plain `Double` inputs). Everything
else is manual-verification only, like `LockScreen/*.swift` and
`System/*.swift` — HID sensor reads, `SCStream` capture, and Metal
rendering all need real hardware and a real lid to exercise.
