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
    let batterySource: BatterySource
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
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
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

    /// Originally matched jackson-storm/dynamicnotch's `headerSection`
    /// exactly (60x60 artwork -- the comment was stale; the code has
    /// always used 50x50 -- 15pt spacing, 16pt/14pt text). Trimmed further
    /// for a more compact card: 44x44 artwork, 14pt/12pt text, tighter
    /// column width to match.
    private func headerSection(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 10) {
            ArtworkView(url: info.artworkURL)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info.title, font: .system(size: 14, weight: .medium), color: .white, width: 160, height: 18)
                MarqueeText(text: info.artist, font: .system(size: 12), color: .white.opacity(0.65), width: 160, height: 16)
            }

            Spacer(minLength: 0)

            WaveformView(isPlaying: info.isPlaying, color: waveformColor)
        }
    }

    /// Sizes/weights match jackson-storm/dynamicnotch's `PlayerControlButton`
    /// usage in `NowPlayingExpandedNotchView.controlsSection`: prev/next at
    /// 22pt, play/pause distinctly bigger at 32pt, both semibold — scaled
    /// down here (18/26pt) for Atelier's narrower panel, same ratio. Their
    /// favorite/output buttons are 21pt, close to prev/next, not tiny.
    private func controlsSection(for info: NowPlayingInfo) -> some View {
        ZStack {
            HStack(spacing: 20) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                Button(action: onPlayPause) {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                }
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
            }

            HStack {
                Button(action: onToggleShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(info.isShuffling ? waveformColor : Color.white.opacity(0.35))
                }

                Spacer(minLength: 0)

                OutputDeviceMenu(
                    devices: outputDevices,
                    currentDeviceID: currentOutputDeviceID,
                    onSelect: onSelectOutputDevice
                )
                .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var emptyState: some View {
        IdleHomeView(batterySource: batterySource)
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

/// A headphones-icon menu listing real output devices from
/// `OutputDeviceManager`, matching the picker in the reference design.
private struct OutputDeviceMenu: View {
    let devices: [AudioOutputDevice]
    let currentDeviceID: AudioDeviceID?
    let onSelect: (AudioDeviceID) -> Void

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
            Image(systemName: "headphones")
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
