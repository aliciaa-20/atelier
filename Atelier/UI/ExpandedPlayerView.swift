import AppKit
import CoreAudio
import SwiftUI

/// The hover-expanded player: artwork, title/artist, a waveform, a
/// draggable scrubber, and transport controls including shuffle and
/// output-device selection. Layout matches jackson-storm/dynamicnotch's
/// `NowPlayingExpandedNotchView` — pulled via `gh api` as ground truth
/// after earlier guesswork didn't match. Their `controlsSection` is the
/// key piece: a `ZStack` of two separate rows, not one row of five evenly
/// spaced buttons — a centered transport cluster (prev/play/next) with a
/// second, edge-pinned row (favorite left, output-device right) overlaid
/// on top. That's what makes the transport buttons read as a tight,
/// deliberate group instead of being stretched across the whole width.
struct ExpandedPlayerView: View {
    let info: NowPlayingInfo?
    let waveformColor: Color
    let outputDevices: [AudioOutputDevice]
    let currentOutputDeviceID: AudioDeviceID?
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onToggleShuffle: () -> Void
    let onSelectOutputDevice: (AudioDeviceID) -> Void

    var body: some View {
        Group {
            if let info {
                player(for: info)
            } else {
                emptyState
            }
        }
        // Horizontal/bottom padding now literally reused from
        // PeekPlayerView (24/9) rather than separately guessed -- Peek is
        // the one view confirmed correctly aligned to the real notch's
        // flat-zone inset, per direct feedback to stop re-guessing values.
        .padding(.horizontal, 24)
        .padding(.bottom, 9)
        // No separate notch-clearance offset here -- this view is only
        // ever shown beneath NotchRootView's own NotchTabBar now, which
        // already clears the real notch (PeekPlayerView-style `+ 4`).
        // A leftover `notchHeight` parameter used to duplicate that
        // clearance on top of the tab bar's own, which is what produced
        // the oversized gap a screenshot caught. This is just the small
        // breathing room between the tab bar and this content, matching
        // ShelfView's own equivalent gap in the same position.
        .padding(.top, 8)
    }

    /// A fixed, even gap between each section (header/scrubber/controls),
    /// not `Spacer(minLength:)` -- flexible spacers stretched to absorb
    /// whatever height the panel had left over from `NotchController`'s
    /// fixed `playerContentHeight`, which is deliberate proximity/grouping
    /// (Apple's own spacing discipline) turned into incidental leftover
    /// space instead. `playerContentHeight` was trimmed to match this
    /// tighter intrinsic height rather than left oversized around it.
    private func player(for info: NowPlayingInfo) -> some View {
        VStack(spacing: 10) {
            headerSection(for: info)
            ScrubberView(duration: info.duration, elapsed: info.elapsed, onSeek: onSeek)
            controlsSection(for: info)
        }
    }

    /// Reuses `PeekPlayerView.content(for:)`'s own values directly (34x34
    /// artwork, cornerRadius 5, 8pt spacing, 92pt text column, headline/
    /// subheadline fonts, same `WaveformView` bar metrics) rather than a
    /// separately hand-tuned set -- Peek is the one view already confirmed
    /// correctly sized against the real notch, so this header now matches
    /// it instead of drifting on its own numbers.
    private func headerSection(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 8) {
            ArtworkView(url: info.artworkURL, cornerRadius: 5)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info.title, font: .headline, color: .white, width: 92, height: 16)
                MarqueeText(text: info.artist, font: .subheadline, color: .white.opacity(0.65), width: 92, height: 16)
            }

            Spacer(minLength: 0)

            WaveformView(isPlaying: info.isPlaying, color: waveformColor, barWidth: 2, barSpacing: 1.3, height: 14)
        }
    }

    /// Sizes/weights match jackson-storm/dynamicnotch's `PlayerControlButton`
    /// usage in `NowPlayingExpandedNotchView.controlsSection` (prev/next
    /// 22pt, play/pause 32pt, both semibold), scaled down for Atelier's
    /// narrower panel and shrunk further per direct feedback.
    private func controlsSection(for info: NowPlayingInfo) -> some View {
        ZStack {
            HStack(spacing: 18) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Button(action: onPlayPause) {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
            }

            // dynamicnotch's own NowPlayingExpandedNotchView.controlsSection
            // gives every button here a fixed frame (42x42 there) rather
            // than a bare glyph -- that's what keeps shuffle/output clear
            // of the panel's rounded corners; a glyph with no surrounding
            // frame sits exactly at its own tight bounding box, which is
            // what let it crowd into the corner in a screenshot. Scaled
            // down to 24x24 to match this panel's smaller scale.
            HStack {
                Button(action: onToggleShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(info.isShuffling ? waveformColor : Color.white.opacity(0.35))
                        .frame(width: 24, height: 24)
                }

                Spacer(minLength: 0)

                OutputDeviceMenu(
                    devices: outputDevices,
                    currentDeviceID: currentOutputDeviceID,
                    onSelect: onSelectOutputDevice
                )
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var emptyState: some View {
        IdleHomeView()
    }
}

/// Spotify's artwork comes back as a URL (invariant 5's sibling fact — see
/// `NowPlayingInfo`); a music-note glyph covers the loading and failure cases
/// so a slow network or a missing image never shows a blank square.
///
/// Loads through `ArtworkImageCache` rather than `AsyncImage` so this and
/// `ArtworkColorLoader` share one fetch per URL instead of racing two.
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            image = nil
            guard let url,
                  let data = await ArtworkImageCache.shared.data(for: url),
                  let nsImage = NSImage(data: data) else { return }
            image = nsImage
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.white.opacity(0.12))
            .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5)))
    }
}

/// Lists real output devices from `OutputDeviceManager`. The label icon
/// reflects the *current* device rather than always showing headphones --
/// "headphones" only makes sense when audio is actually routed to
/// AirPods/a headset; otherwise it's the same "speaker.wave.2.fill" glyph
/// Apple's own Control Center Sound module uses for built-in output.
private struct OutputDeviceMenu: View {
    let devices: [AudioOutputDevice]
    let currentDeviceID: AudioDeviceID?
    let onSelect: (AudioDeviceID) -> Void

    private var currentDeviceIsAirPods: Bool {
        devices.first(where: { $0.id == currentDeviceID })?.isAirPods ?? false
    }

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    onSelect(device.id)
                } label: {
                    if device.id == currentDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: currentDeviceIsAirPods ? "headphones" : "speaker.wave.2.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Adapted from jackson-storm/dynamicnotch's `PlayerProgressBar` — pulled
/// via `gh api` after a below-the-bar time-label layout didn't match the
/// reference. Their actual layout is one row: elapsed time, then the bar,
/// then duration, all inline — not the bar with labels stacked underneath.
struct ScrubberView: View {
    let duration: TimeInterval
    let elapsed: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragValue: TimeInterval?
    @State private var dragging = false

    private var displayedElapsed: TimeInterval { dragValue ?? elapsed }

    var body: some View {
        HStack(spacing: 8) {
            Text(TimeFormatting.mmss(displayedElapsed))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))

            GeometryReader { geo in
                let progress = duration > 0 ? min(max(displayedElapsed / duration, 0), 1) : 0
                // Track thickens while dragging, same tactile cue as
                // boring.notch's `CustomSlider`; the fill's own width
                // animates on `displayedElapsed` so poll-driven updates
                // (every 0.25s while expanded) ease into place instead of
                // visibly stepping.
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.85)).frame(width: geo.size.width * progress)
                }
                .frame(height: dragging ? 6 : 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragging = true
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            dragValue = ratio * duration
                        }
                        .onEnded { _ in
                            if let dragValue {
                                onSeek(dragValue)
                            }
                            dragValue = nil
                            dragging = false
                        }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
                // Only ease poll-driven updates; a live drag must track the
                // finger 1:1, not lag behind an animation.
                .animation(dragging ? nil : .easeOut(duration: 0.2), value: displayedElapsed)
            }
            .frame(height: 14)

            Text(TimeFormatting.mmss(duration))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
