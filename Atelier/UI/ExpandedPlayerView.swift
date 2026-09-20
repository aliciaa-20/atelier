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
        // Horizontal padding widened (20->26) per direct feedback that
        // content sat too close to the panel's rounded corners.
        .padding(.horizontal, 26)
        // Widened (10->16) so the transport row clears the bottom edge
        // with real breathing room instead of reading as pinned to it --
        // same direct feedback pass as the horizontal padding above.
        .padding(.bottom, 16)
        // No separate notch-clearance offset here -- this view is only
        // ever shown beneath NotchRootView's own NotchTabBar now, which
        // already clears the real notch (PeekPlayerView-style `+ 4`). A
        // leftover `notchHeight` parameter used to duplicate that
        // clearance on top of the tab bar's own, producing a large dead
        // gap between the dots and the actual content. This is just the
        // small breathing room between the tab bar and this content,
        // matching ShelfView's own equivalent gap in the same position.
        .padding(.top, 6)
    }

    private func player(for info: NowPlayingInfo) -> some View {
        VStack(spacing: 0) {
            headerSection(for: info)
            Spacer(minLength: 4)
            ScrubberView(duration: info.duration, elapsed: info.elapsed, onSeek: onSeek)
            Spacer(minLength: 4)
            controlsSection(for: info)
        }
    }

    /// Shrunk from an earlier pass (50pt artwork, 15/13pt text, 170pt text
    /// column) per direct feedback that the player read as oversized and
    /// too spaced-out compared to iOS's own Control Center Now Playing
    /// module -- that reference uses a noticeably smaller artwork-to-text
    /// ratio and tighter line spacing than jackson-storm/dynamicnotch's
    /// own (larger, macOS-native-styled) original. Text column narrowed to
    /// 150 to match `ScrubberView`'s own already-correct full-width framing
    /// (see the marquee/scrubber fix queued for this same rebuild).
    private func headerSection(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 10) {
            ArtworkView(url: info.artworkURL)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info.title, font: .system(size: 14, weight: .medium), color: .white, width: 150, height: 18)
                MarqueeText(text: info.artist, font: .system(size: 12), color: .white.opacity(0.65), width: 150, height: 18)
            }

            Spacer(minLength: 0)

            WaveformView(isPlaying: info.isPlaying, color: waveformColor)
        }
    }

    /// Sizes trimmed from an earlier pass (18/26pt prev-next/play, 24pt
    /// spacing) to read closer to iOS's own Control Center transport row --
    /// smaller glyphs, tighter spacing between them, per direct feedback
    /// that the whole player took up too much room. Still keeps
    /// jackson-storm/dynamicnotch's own layout idea: a `ZStack` of two rows
    /// (centered transport cluster, edge-pinned shuffle/output) rather than
    /// one row of five evenly spaced buttons.
    private func controlsSection(for info: NowPlayingInfo) -> some View {
        ZStack {
            // Bumped back up slightly (15/20 -> 17/23) per direct feedback
            // that the previous pass's trim read as a bit too small.
            HStack(spacing: 20) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 17, weight: .semibold))
                }
                Button(action: onPlayPause) {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 23, weight: .semibold))
                }
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 17, weight: .semibold))
                }
            }

            // A bare glyph in the corner read as an accidental stray mark,
            // not a button -- per direct feedback ("floating in space...
            // do not seem intentionally there"). A soft translucent
            // circle backdrop (iOS Control Center's own convention for
            // its secondary buttons) gives each one a visible boundary/
            // affordance instead of just an icon sitting on bare black.
            HStack {
                Button(action: onToggleShuffle) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(info.isShuffling ? waveformColor : Color.white.opacity(0.65))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }

                Spacer(minLength: 0)

                OutputDeviceMenu(
                    devices: outputDevices,
                    currentDeviceID: currentOutputDeviceID,
                    onSelect: onSelectOutputDevice
                )
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .padding(.horizontal, 4)
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
        HStack(spacing: 6) {
            Text(TimeFormatting.mmss(displayedElapsed))
                .font(.system(size: 10, weight: .medium, design: .rounded))
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
            .frame(height: 12)

            Text(TimeFormatting.mmss(duration))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
