# Atelier — Feature Backlog

A categorized list of features pulled from a survey of every reference notch
app tracked in `check-reference-apps-first` (boring.notch, Atoll,
DynamicNotchKit, dynamicnotch, notchify, NotchBar, mew-notch, NotchDrop,
AgentPulse, QuartzNotch, NotchIA — see that skill for repo links). Each item
below is a candidate the user chose to pull into Atelier; each phase in
[ROADMAP.md](ROADMAP.md) draws its scope from here.

`check-reference-apps-first` still applies to every item: pull the real
source before designing, don't reason from the README summary alone.

**Explicitly excluded:** clipboard history (notchify, Atoll, QuartzNotch,
NotchIA all ship it) — the user already uses Maccy for this.

---

## 1. Now-Playing & Live Activity core

| Feature | Source(s) | Depends on |
|---|---|---|
| Elevate now-playing into a first-class Live Activity (not just peek/pill) | User-requested, generalizing dynamicnotch/Atoll/QuartzNotch's Live Activity pattern | §5 architecture |
| Lock-screen now-playing widget | User-requested; mew-notch ("notch visible on lock screen"), QuartzNotch (lock-screen lyrics), dynamicnotch (lock-screen live-activity surfaces) | §5 architecture |
| Real-time audio visualizer | boring.notch, Atoll, QuartzNotch, dynamicnotch | — |
| Synced lyrics | QuartzNotch, dynamicnotch, NotchIA | — |

**Feasibility flag — lock-screen widget:** macOS has no public API for
third-party lock-screen widgets (WidgetKit's lock-screen surface is
iOS-only). What reference apps call "lock screen" support is likely their
own floating panel staying drawn over the lock-screen image, not a true
system-integrated widget with OS-granted lock-screen access. Before
designing this, read the actual window/panel-level code in mew-notch,
QuartzNotch, or dynamicnotch (not just their README) to confirm what's
really happening — a `check-reference-apps-first` spike, not an assumed
capability.

**Resolved:** confirmed exactly that — Atoll and QuartzNotch both delegate
an ordinary `NSWindow` into a private CGS space (`SkyLightSpaceOperator`/
`SkyLightWindow`) rather than using any OS-granted lock-screen surface.
Implemented the same way; see `docs/ROADMAP.md`'s Phase 11 entry.

---

## 2. Interaction & feel

| Feature | Source(s) |
|---|---|
| Gesture controls — swipe to open/close, horizontal swipe to seek/skip | Atoll, dynamicnotch |
| Physics-based spring/"jelly" morph animation mimicking real iOS Dynamic Island motion | dynamicnotch |
| Camera mirror mode — *shipped (Phase 14, ADR 0016)* | boring.notch, notchify, QuartzNotch |

---

## 3. System HUD replacement

| Feature | Source(s) |
|---|---|
| Volume/brightness HUD replacement | mew-notch, boring.notch, NotchIA |
| Battery/charging indicator | boring.notch, dynamicnotch, Atoll |
| Keyboard backlight HUD | boring.notch |
| Power state / time remaining | mew-notch |
| Suppress stock macOS HUDs while ours is shown | mew-notch |

---

## 4. File shelf & related utilities

| Feature | Source(s) |
|---|---|
| File shelf drag & drop | NotchDrop, boring.notch, mew-notch, notchify, QuartzNotch, NotchIA |
| AirDrop integration | NotchDrop, boring.notch |
| File format converter | NotchIA |

---

## 5. Live Activities / system alerts (extensible framework)

| Feature | Source(s) |
|---|---|
| Extensible "Live Activity" state system — the architecture other items plug into | QuartzNotch, Atoll, dynamicnotch |
| Focus mode, screen recording, downloads, personal hotspot, Bluetooth, Wi-Fi, VPN state alerts | dynamicnotch, Atoll, QuartzNotch |

This is the foundational item: rather than hard-coding each new surface
(now-playing peek, lock-screen widget, system alerts, productivity widgets)
into `NotchState` one at a time, generalize into a `NotchWidget`/`LiveActivity`
protocol they all conform to — closer to NotchBar's plugin-widget
architecture than to bolting features on individually.

---

## 6. Productivity widgets

| Feature | Source(s) |
|---|---|
| Calendar ✅ (`Widgets/Calendar/`, read-only EventKit: week strip + day agenda, swipe/tap; reminders not built) | boring.notch, Atoll, notchify, QuartzNotch, NotchIA |
| Weather ✅ (`Widgets/Weather/`, Open-Meteo + CoreLocation; glance + detail card on idle Home; [ADR 0015](decisions/0015-weather-open-meteo-corelocation.md)) | Atoll, Sapphire |
| Quick notes | notchify |
| Timers / Pomodoro | QuartzNotch, NotchIA, Atoll |
| Color picker ✅ (`Widgets/ColorPicker/`, `NSColorSampler`) | Atoll |

---

## Settings window (ROADMAP Phase 16)

Shipped: a native Settings window (sidebar panes, instant apply), launch at
login via `SMAppService`, drag-to-reorder tabs (Home pinned first), and a
Permissions status pane. See ADR 0018. The window, launch at login and the
permission rows are manually verified only, like `System/*.swift`.

## 7. System resource monitor

| Feature | Source(s) |
|---|---|
| CPU / GPU / memory / network / disk usage, SMC-based temperature | Atoll (adapted from the "Stats" project), NotchBar |

**Partial slice shipped:** CPU load % and memory-used % only, via the
public Mach `host_statistics`/`host_statistics64` APIs (`SystemMonitorSource`,
`Atelier/Widgets/SystemMonitor/`) — no entitlement or private symbol
needed. GPU, network, disk usage, and SMC-based temperature/IOReport
frequency sampling remain **not implemented**; those need private/SMC
access this pass deliberately avoided. Polls every 4s, matching the
lightweight-by-design principle.

Two access points:
- **Pill** — lowest priority in the stack (`NotchLiveActivityPriority.systemMonitor`),
  `peeksOnChange == false` (same ambient-status treatment as Battery). Bare
  "23% / 61%" in the pill's two ~18pt flanks, only visible when nothing
  higher-priority (now playing, battery, recording) is occupying the pill.
- **Tab** — a third `NotchPage.systemMonitor` tab alongside Home/Shelf
  (`SystemMonitorPageView.swift`), always shown (no settings toggle yet,
  unlike Shelf). Full-size labeled capsule bars for CPU/Memory, tap to
  switch via `NotchTabBar`, reflects the live reading regardless of pill
  priority.

**Not yet manually verified on-device** (build + unit tests pass; whether
the Mach calls return sane numbers on real hardware, and whether the tab/
pill actually look right, hasn't been visually confirmed).

---

## 8. Dev-agent session monitoring

| Feature | Source(s) |
|---|---|
| Live session tracking for Claude Code / Cursor / Codex (duration, tool activity, context/rate-limit progress) | AgentPulse, NotchIA |
| Permission-approval UI (Allow Once / Always / Deny) surfaced from the notch | AgentPulse |

**Feasibility note:** this needs a hook-install + IPC bridge (AgentPulse
uses a Unix domain socket between a bridge binary and the app) between
Claude Code/Cursor/Codex and Atelier — a genuinely new subsystem, not a
variant of `NowPlayingSource`. Likely the most novel and highest-effort item
in this whole backlog; sequenced last for that reason.

---

## 9. Terminal & LLM cost tracking

| Feature | Source(s) |
|---|---|
| Built-in terminal | Atoll |
| LLM usage/cost tracking | Atoll; see also OpenUsage and OpenRouter in `CLAUDE.md`'s reference-apps list |

Re-added to the backlog. `check-reference-apps-first` still applies: OpenUsage
and OpenRouter are cited there as adaptable sources, not dependencies to pull
in directly — CLAUDE.md's no-third-party-dependencies rule still governs the
implementation.

---

## 10. Teleprompter / Ghost Mode

| Feature | Source(s) |
|---|---|
| Script scrolling near the camera/notch, hidden from screen shares and recordings, voice-synced pacing, AI rehearsal coaching, live captions | [CueNotch](https://cuenotch.com) (primary reference — closest to what's wanted), [jpomykala/NotchPrompter](https://github.com/jpomykala/NotchPrompter), [Avocado](https://avocadonotch.com) |

CueNotch and Avocado are commercial apps (not open-source) — credited by
name for the product idea, not pulled as source. NotchPrompter is
open-source MIT and was pulled directly: its `PrompterWindow.swift`
confirms the Ghost Mode mechanism below (`window.sharingType = .none`) and
its `AudioMonitor.swift` is a simple mic-RMS meter, not the voice-synced
pacing item 4 needs. Direct feedback split this into two tiers, in
priority order:

**Tier 1 (wanted, in order):**
1. **Scrolling script view** — a `NotchPage` tab, same shape as
   `SystemMonitorPageView`/`ShelfView`: a `ScrollView` with a timer-driven
   auto-scroll, manual pace control. No new subsystem. **Focus Guide**
   (Avocado): dim already-read lines, highlight the current line — a small,
   self-contained addition to this same view, no new subsystem.
2. **Ghost Mode** — `NSWindow.sharingType = .none` excludes a window from
   screen capture (ScreenCaptureKit, screenshots, Zoom/Meet capture) while
   staying visible on the real display. Public AppKit API, no entitlement,
   no private symbol. Confirmed via NotchPrompter's own use of it. Atelier
   already tracks screen-recording state (`ScreenRecordingSource`), so this
   slots into the existing pattern rather than needing new plumbing.
3. **Script library** — folders + search, same shape as `ShelfStore`'s
   existing JSON-manifest + file-storage pattern (`Shelf/ShelfStore.swift`).
4. **Voice-synced scrolling** — tracks actual speaking pace via
   `SFSpeechRecognizer` streaming from the mic. Avocado confirms this is
   the real shape (on-device speech recognition, adaptive to natural
   reading pace, not just a volume meter — NotchPrompter's `AudioMonitor`
   is not this). A real subsystem (live audio pipeline, latency/accuracy
   tuning), not a widget-sized addition — the first item in this list that
   needs its own design pass before starting.

**Tier 2 (wanted, lower priority):**
5. **AI rehearsal coach** ("Magic Polish", pace/posture feedback) — needs
   an LLM backend and likely Vision-framework posture analysis from the
   camera. Runs against CLAUDE.md's no-third-party-dependencies-without-
   discussion rule and introduces a different trust model (network calls)
   than anything else in Atelier — needs its own conversation before
   scoping, not just a design pass.
6. **Live meeting captions** — system audio capture + speech-to-text,
   another sizable subsystem on top of #4.

**Feasibility note:** items 1–3 are genuinely small, in-pattern additions.
Item 4 is a real subsystem on its own. Items 5–6 are close to a second,
network-connected app living inside Atelier's shell — treat as a separate
phase with its own plan, not folded into whichever phase ships 1–4.

---

## 11. Keep awake with lid closed

| Feature | Source(s) |
|---|---|
| Keep the Mac running (agents, builds, downloads) with the lid closed, without needing an external display | [Aboudjem/Sleepless](https://github.com/Aboudjem/Sleepless) (MIT, pulled directly), [Amphetamine](https://apps.apple.com/in/app/amphetamine/id937984704?mt=12), [Never Sleep](https://apps.apple.com/us/app/never-sleep-even-lid-closed/id1574505861?mt=12) |

**User-requested, approved to build — spec written, not yet implemented.**
See [the design spec](superpowers/specs/2026-09-23-keep-awake-lid-closed-design.md)
for the full architecture, consent/revoke requirements, and safety nets.
Motivation: coding agents (Claude Code sessions etc.) should keep running
unattended when the lid is closed, not just while the screen is open.

**Mechanism (confirmed via Sleepless's source):** ordinary power
assertions (`caffeinate`-style `IOPMAssertionCreateWithName`) do **not**
override a physical lid-close sleep event — that needs `sudo pmset -a
disablesleep 1`, an undocumented-but-real `pmset` flag that sets
`SleepDisabled=Yes` in IORegistry and blocks idle + lid-close sleep, even
on battery, with no external display required.

**The real tradeoff, not a technical detail:** this requires root every
time it toggles. Sleepless's answer is a one-time admin authorization
(Touch ID/password) that installs a narrowly-scoped `/etc/sudoers.d`
drop-in — passwordless, but *only* for the exact `pmset -a disablesleep
[0|1]` invocation. After that one grant, toggling needs no further
prompts. It's runtime-only (`SleepDisabled` resets to 0 on reboot) and
the grant itself persists on disk until revoked. This is a materially
different risk shape than anything else in Atelier — everything else so
far reads system state or uses public, unprivileged APIs; this one writes
a standing passwordless-sudo grant to the machine. Needs an explicit
go/no-go from the user before any implementation, independent of how
small the actual UI ends up being.

**If approved, safety nets worth carrying over from Sleepless:** an
auto-off timer, a battery-floor cutoff (never drains to empty), a Low
Power Mode auto-off, and never re-arming itself after reboot or login —
none of which add a daemon or persist OS state beyond the one sudoers
grant.

---

## Not pulled from the survey

- **Clipboard history** — excluded, user already uses Maccy.
- **On-device AI news digest, video/audio downloader (NotchIA)** — out of
  scope, unrelated to Atelier's purpose.
- **DynamicNotchKit** — not a feature source, a reusable SPM library for
  notch windows. Useful only as an architectural reference for Phase 6's
  Live Activity work, not as a feature to adopt.
