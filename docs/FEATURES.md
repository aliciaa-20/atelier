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

---

## 2. Interaction & feel

| Feature | Source(s) |
|---|---|
| Gesture controls — swipe to open/close, horizontal swipe to seek/skip | Atoll, dynamicnotch |
| Physics-based spring/"jelly" morph animation mimicking real iOS Dynamic Island motion | dynamicnotch |
| Camera mirror mode | boring.notch, notchify, QuartzNotch |

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
| Calendar / reminders (EventKit) | boring.notch, Atoll, notchify, QuartzNotch, NotchIA |
| Quick notes | notchify |
| Timers / Pomodoro | QuartzNotch, NotchIA, Atoll |
| Color picker | Atoll |

---

## 7. System resource monitor

| Feature | Source(s) |
|---|---|
| CPU / GPU / memory / network / disk usage, SMC-based temperature | Atoll (adapted from the "Stats" project), NotchBar |

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

## Not pulled from the survey

- **Clipboard history** — excluded, user already uses Maccy.
- **Built-in terminal, LLM usage/cost tracking (Atoll)** — third-party
  dependency-heavy, out of scope per `CLAUDE.md`'s no-dependencies rule.
- **On-device AI news digest, video/audio downloader (NotchIA)** — out of
  scope, unrelated to Atelier's purpose.
- **DynamicNotchKit** — not a feature source, a reusable SPM library for
  notch windows. Useful only as an architectural reference for Phase 6's
  Live Activity work, not as a feature to adopt.
