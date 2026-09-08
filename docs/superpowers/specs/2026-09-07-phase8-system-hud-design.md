# Phase 8 — System HUD replacement

## Context

`FEATURES.md §3` lists five items: volume/brightness HUD replacement,
battery/charging indicator, keyboard backlight HUD, power state/time
remaining, and suppressing the stock macOS HUDs while ours shows.

Two references were read via `gh api` per `check-reference-apps-first`
before designing:

- **monuk7735/mew-notch**'s `MediaKeyManager.swift`: a single global
  `CGEventTap` on `kCGEventSystemDefined` events, filtered to
  `NX_KEYTYPE_SOUND_UP`/`_DOWN`/`_MUTE`/`_BRIGHTNESS_UP`/`_DOWN`. On a
  matching key it applies the change itself and returns `nil` from the tap
  callback — that single `nil` return is the entire "suppress the stock
  HUD" mechanism; the system never sees the key event, so it never shows
  its own overlay. Requires `AXIsProcessTrusted()` (Accessibility
  permission) before the tap installs. Volume goes through `AudioOutput.m`
  — genuinely public CoreAudio (`AudioObjectGetPropertyData`/
  `SetPropertyData` on the default output device, `AudioServices` for
  mute) — no private API risk. Brightness goes through `Brightness.m`,
  which declares `extern int DisplayServicesGetBrightness(...)` /
  `DisplayServicesSetBrightness(...)` — an undocumented, private framework
  symbol with no public alternative and no stability guarantee across
  macOS versions. Same risk category as ADR 0001's `MediaRemote` rejection,
  except this one actually works today (mew-notch ships it).
- **TheBoredTeam/boring.notch**'s `BrightnessManager.swift`/
  `KeyboardBacklightManager.swift`: both route through a privileged
  **XPC helper tool** (`BoringNotchXPCHelperProtocol`,
  `SMJobBless`/`SMAppService`-registered daemon) rather than calling
  `DisplayServices` in-process. Keyboard backlight specifically needs
  this — IOKit backlight control requires elevated privileges a normal
  sandboxed/unprivileged app process doesn't have, unlike screen
  brightness which mew-notch proves works fine unprivileged.

**Decision, confirmed with the user:**

1. This phase builds **volume + brightness HUD replacement only**.
   Keyboard backlight is deferred to a later phase — it requires a whole
   new privileged-helper-tool subsystem (first of its kind in Atelier),
   a much bigger commitment than the event-tap mechanism this phase uses.
2. The private `DisplayServices` risk is accepted (single-machine,
   private-repo project) and documented in a new ADR, with **fail-open**
   behavior: if the private symbols are ever missing/return an error,
   brightness key interception stops applying the change itself and lets
   the key event pass through untouched — the stock HUD reappears rather
   than the feature silently doing nothing.
3. "Battery/charging indicator" is not new work — Phase 6 already shipped
   an always-visible Battery pill. This phase only *extends* it with
   estimated time-to-full/time-remaining, reusing the same
   `IOPSCopyPowerSourcesInfo` call `BatterySource` already makes (the
   description dictionary already carries `kIOPSTimeToEmptyKey`/
   `kIOPSTimeToFullChargeKey` — no new API, just reading fields not yet
   read).
4. "Suppress stock macOS HUDs" is not a separate mechanism — it falls out
   of the `CGEventTap` returning `nil`. No additional design needed.
5. Accessibility permission (a new TCC type for Atelier — Automation was
   used for AppleScript/Spotify) gets a menu-bar item ("Grant
   Accessibility Access...") that deep-links to System Settings via
   `x-apple.systempreferences:`, shown whenever `AXIsProcessTrusted()` is
   false — matching the "visible grant-access path when TCC is denied"
   posture the roadmap already calls for generally (Phase 16), arriving
   here out of necessity rather than waiting for the Settings window.

## Non-goals

- Keyboard backlight HUD and its privileged XPC helper tool — later
  phase, once the event-tap pattern here is proven and the team wants to
  take on the helper-tool infrastructure commitment.
- Continuous/analog volume or brightness scrubbing UI in the HUD itself —
  matches the real macOS HUD (discrete step per key press), not a new
  interaction.
- A general Settings window for managing this permission — Phase 16.
  The menu-bar deep-link is a stopgap, not the final UX.
- Mouse/trackpad-driven volume or brightness changes — this phase only
  intercepts the physical function keys, matching every reference app's
  scope for "HUD replacement."

## Architecture

```
NotchController ──owns── MediaKeyInterceptor (new, AppKit)
        │                       │
        │                       ├── installs CGEventTap (kCGEventSystemDefined)
        │                       ├── on match: apply change, return nil
        │                       └── publishes into VolumeSource/BrightnessSource
        │
        ├── LiveActivityCoordinator
        │     └── [LiveActivitySource]
        │           ├── NowPlayingLiveActivitySource   (priority 10)
        │           ├── VolumeSource        (new, priority 20)
        │           ├── BrightnessSource    (new, priority 19)
        │           ├── AirPodsSource                  (priority 6)
        │           └── BatterySource (extended: + time-remaining) (priority 5)
        │
        └── AccessibilityPermission (new, thin AppKit helper)
              └── AXIsProcessTrusted() check + System Settings deep-link
```

### `MediaKeyInterceptor` — AppKit, manual-verification only

`Atelier/System/MediaKeyInterceptor.swift`. Structurally adapted from
mew-notch's `MediaKeyManager` (credited in a source comment): one
`CGEvent.tapCreate` on `.cgSessionEventTap` / `.headInsertEventTap`,
`eventsOfInterest` = `kCGEventSystemDefined`. On a recognized key code
(sound up/down/mute, brightness up/down):

- **Volume/mute**: apply via public CoreAudio (`AudioObjectSetPropertyData`
  on `kAudioHardwarePropertyDefaultOutputDevice` +
  `kAudioDevicePropertyVolumeScalar`/`kAudioDevicePropertyMute`) — a new
  small wrapper, not reusing `OutputDeviceManager` (that type manages
  *which* output device is default, a different concern from *this*
  device's volume/mute).
- **Brightness**: apply via `DisplayServicesGetBrightness`/
  `SetBrightness` (private, `extern`-declared symbols, weak-linked — no
  bridging header needed; declared directly in Swift via the same
  `@_silgen_name`-free `extern` pattern Swift can use for C symbols
  resolvable at link time, confirmed feasible during implementation
  planning). If the call fails or the symbol can't be resolved: **do not
  return `nil`** from the tap callback for that key — pass the event
  through so the stock HUD shows (fail-open, per Decision #2 above).

Publishes into `VolumeSource`/`BrightnessSource` (see below) rather than
directly touching `LiveActivityCoordinator` — same seam discipline as
`NowPlayingCoordinator`/`BatterySource`.

This file is manual-verification only (real hardware keys, a real
`CGEventTap`, real Accessibility permission) — no unit test coverage,
matching this codebase's existing treatment of `NotchGestureModifier` and
`AppleScriptRunner`. Any pure logic extractable from it (e.g. key-code →
change-amount mapping, or the fail-open decision itself) should be pulled
into a small pure helper and unit-tested the same way
`NotchGestureInterpreter` was — exact extraction boundary is an
implementation-time call once the actual code shape is visible.

### `VolumeSource` / `BrightnessSource` — new `LiveActivitySource`s

`Atelier/Widgets/Volume/VolumeSource.swift`,
`Atelier/Widgets/Brightness/BrightnessSource.swift`. Each publishes
content only while its HUD is transiently visible (`nil` the rest of the
time) — same "nil means nothing to show" contract as `BatterySource`.
`NotchLiveActivityPriority` (currently `nowPlaying = 10, airpods = 6,
battery = 5`) gains:

```swift
static let volume = 20
static let brightness = 19
```

Both above `nowPlaying` — unlike Battery's deliberate pill-only,
`interruptContent`-based design (Phase 6), a real system HUD interrupts
*anything* on screen immediately. Plain priority ordering in the existing
`LiveActivityStack` already gives this for free: no new coordinator
mechanism needed, `interruptContent` stays exactly as Phase 6 left it,
used only by `BatterySource`.

`peeksOnChange = true` for both (the default) — every key press should
pop the peek, matching the real HUD's behavior. Decay duration is a new
constant, on-device-tuned to feel like the stock HUD's own timing rather
than reusing `peekDuration`'s 2.5s (real system HUDs decay faster, closer
to ~1–1.5s, per casual observation of stock macOS — confirmed/tuned for
real during implementation, not asserted here).

### `BatterySource` extension

Add `timeRemaining: TimeInterval?` to `BatteryActivityState`/
`BatteryActivityContent`, read from `description[kIOPSTimeToEmptyKey]`
(discharging) or `description[kIOPSTimeToFullChargeKey]` (charging) in
`BatterySource.poll()` — both already available in the same dictionary
`poll()` reads today, per Apple's `IOPowerSources.h`. `-1` means "still
calculating," matching Apple's own documented sentinel — surface as "—" or
omit the field rather than a nonsense duration. Formatting logic
(minutes → "2h 14m" style) is pure and unit-testable the same way
`TimeFormatting` already is for playback position.

### Accessibility permission

`Atelier/System/AccessibilityPermission.swift` — thin: `AXIsProcessTrusted()`
plus a `static func openSystemSettings()` using
`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`.
`AtelierApp.swift`'s menu gains a conditional item — "Grant Accessibility
Access..." — shown only when `AXIsProcessTrusted()` is false, checked each
time the menu opens (matches how `AtelierSettings` toggles already read
live state rather than caching it).

`MediaKeyInterceptor` checks `AXIsProcessTrusted()` before installing the
tap and again periodically (or on menu-open, reusing the same check) —
if permission is revoked after the tap was installed, `CGEventTap`
delivers `.tapDisabledByUserInput`/similar, at which point the interceptor
should stop cleanly rather than spin, matching mew-notch's
`.tapDisabledByTimeout` re-enable handling as the template for this class
of event.

## Testing

- Pure logic extracted from `MediaKeyInterceptor` (key-code mapping,
  fail-open decision) — unit-tested once the extraction boundary is clear
  at implementation time.
- `BatteryActivityState`'s time-remaining formatting — pure, unit-tested
  like the existing threshold logic.
- `MediaKeyInterceptor` itself, the `CGEventTap` installation, and the
  actual on-device suppression behavior (does the stock HUD really not
  appear) — manual-verification only, explicitly documented as such.
- Accessibility permission flow (grant, revoke-while-running, deep-link
  opens the correct System Settings pane) — manual-verification only.

## Migration

No existing behavior changes unless a volume/brightness key is pressed.
`BatterySource`'s existing threshold/pill/peek behavior is unaffected by
the time-remaining addition (new optional field, not a new state).
`LiveActivityStack`'s priority ordering already supports inserting new
higher-priority sources without changes — this is the second/third proof
(after Battery/AirPods) that the seam scales, per Phase 6's design intent.

## New ADR (to write once implementation confirms the approach works)

Document: the `DisplayServices` private-API choice, why no public
alternative exists (checked during Phase 8 design — Apple's own
`Brightness` public framework APIs are for external displays via DDC/CI,
not the built-in panel), the fail-open fallback behavior, and what to do
if a future macOS update breaks the symbols (most likely: re-check
mew-notch/boring.notch for how they adapted, per this project's existing
`check-reference-apps-first` convention).
