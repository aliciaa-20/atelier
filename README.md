<div align="center">

# Atelier

### A Dynamic Island for your Mac's notch.

Atelier turns the dead space above your screen into a living surface —
a now-playing player on hover, a slim pill while music plays, and a
quick peek for whatever's happening on your system. Shaped to look
like it belongs there, not bolted on.

</div>

---

## What it does

**Now playing, front and center.** Artwork, scrubber, transport
controls, and a 6-bar waveform that reacts to the *actual audio
playing* — driven by a real-time system audio tap, not a fake pulse.
Works with Spotify and Apple Music, automatically following whichever
one is actually playing.

**A system HUD that finally looks right.** Volume and brightness get
their own pill and peek instead of the stock macOS overlay — same
material, same motion language as everything else in the notch.

**A place to park a file.** Drop something on the notch, grab it
later. Auto-swept after 24 hours, so it never turns into a junk
drawer.

**Live system state, always in view.** Battery, screen recording, and
more surface through one shared pill — one glance, no digging through
menu bars.

**Follows you to the lock screen.** The now-playing card doesn't
disappear the moment you step away.

**Built for touch and trackpad instincts.** Swipe to open, close, or
skip tracks — tuned with real spring physics, not a linear animation
pretending to be one.

**A mirror before you're on camera.** Tap the Camera tab for a live
self-view before a call. The camera only turns on while you're
looking, and nothing is ever recorded.

**A calm home base.** Home, Shelf, System Monitor, and Calendar tabs
give you somewhere to land when nothing's playing — a week strip with
a line of personality for each day, one swipe away from your full
calendar.

**A teleprompter that scrolls itself.** Paste a script and read at
your pace — literally. Turn on **Follow my voice** and the script
tracks what you're actually saying, on-device, and waits when you
pause. Ghost Mode keeps it invisible to screen shares and recordings.

**Weather, at a glance.** A quiet read on the idle Home card — tap for
the full forecast, five days out.

**Light on your battery, on purpose.** Everything idles to nothing
when it isn't visible. A menu-bar accessory that behaves like one.

---

## Requirements

- macOS 27.0+
- Xcode 26+

## Settings

Click the menu-bar icon → **Settings** (⌘, while the menu is open).

| Pane | What lives there |
|---|---|
| General | Launch at login, peek behavior, gestures |
| Appearance | Liquid Glass |
| Tabs | Enable and drag to reorder — Home stays pinned first |
| Widgets | Calendar, Camera, Color Picker |
| Teleprompter | Script, reading speed, font, Ghost Mode, shortcuts |
| Permissions | Live status for everything below, with a shortcut into System Settings |

## Permissions

Atelier only asks for what a given feature actually needs, when you
turn that feature on — and degrades gracefully, not silently, if you
say no.

| Permission | Why |
|---|---|
| Automation | Reads now-playing data from Spotify and Apple Music, and jumps Calendar.app to a day |
| Calendars (full access) | Read-only — shows your week and events. Atelier never adds or edits anything |
| Camera | Powers the Camera tab's live mirror. Requested only on your first tap |
| Location (While Using) | Approximate, one-shot, just to fetch a forecast. Weather simply hides if declined |
| Microphone + Speech Recognition | Teleprompter voice sync — on-device word tracking, only while actively listening |
| Accessibility | Lets Atelier intercept volume/brightness/mute keys for its own HUD |
| System Audio Recording Only | Powers the live waveform via a system-wide audio tap |
| Screen & System Audio Recording | Renders the desktop bend effect as the lid closes. Only runs while actively bending; nothing is recorded or saved |

**Network:** the only outbound calls are Spotify/Apple Music artwork,
a weather lookup against `api.open-meteo.com` (rounded coordinates
only, no account or key), and — for Apple Music streaming tracks only
— an artwork lookup against `itunes.apple.com`. Nothing else leaves
the machine.

---

<div align="center">

Built for one Mac. A companion, not a product with a roadmap of ads.

*Full development history and open items live in [`docs/ROADMAP.md`](docs/ROADMAP.md).*

</div>
