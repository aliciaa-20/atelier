import SwiftUI

/// Atelier's own now-playing card for the lock screen (see the design
/// spec) -- collapsed by default (artwork + title/artist, with parallax),
/// expands on hover to a larger view with a real scrubber and transport
/// controls. Local `@State`, not `NotchStateMachine` -- this window is
/// entirely separate from the notch. Observes `NowPlayingCoordinator`
/// directly (not a snapshot `NowPlayingInfo`) so the card stays live for
/// as long as the window exists, the same way any other SwiftUI subtree
/// reacts to a `@Published` change.
///
/// One persistent view hierarchy for both states, sized by scalar
/// properties keyed on `isExpanded` -- matching Ebullioscopic/Atoll's own
/// `LockScreenMusicPanel` (`controlFrameSize`/`playPauseIconSize`/etc.).
/// An earlier version swapped between two separate `if isExpanded {}`
/// subtrees, which SwiftUI animates as a remove-then-insert rather than a
/// smooth resize -- keeping one tree and only animating its scalar
/// properties is what makes the hover morph read as continuous motion.
///
/// `cardCornerRadius` is a fixed constant, not interpolated between states
/// (an earlier version animated it 24->30) -- both Ebullioscopic/Atoll and
/// Clayton630/QuartzNotch's own lock-screen panels use one fixed
/// `panelCornerRadius` regardless of expand state. Animating it made the
/// panel's curve and the artwork's own (fixed-ratio) curve drift out of
/// sync mid-hover, which read as "the rounded corners don't match".
/// `artworkCornerRadius` stays proportional to `artworkSize` for the same
/// reason a container and its nested content should look concentric (see
/// the Liquid Glass shape system: parent radius minus padding for nested
/// shapes) rather than using an unrelated fixed value at each size step.
///
/// The card's background is a blurred, darkened copy of the track's own
/// artwork, not a flat tint or the system `.glassEffect()` -- that's what
/// iOS's own Lock Screen Now Playing widget and Control Center do, and
/// it's why they never look like a generic dark rounded rectangle: the
/// "glass" is built from the content, not a translucency effect sitting
/// on top of the wallpaper. Stacking the system glass material on top of a
/// custom blur would also be glass-on-glass, which Liquid Glass's own
/// design rules call out as incorrect.
struct LockScreenMusicCardView: View {
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    /// Shared with `NotchController`/the main notch panel via
    /// `LockScreenPanelController` -- not a second tap. See that
    /// controller's own `audioTap` doc comment for why.
    @ObservedObject var audioTap: AudioTap
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isExpanded = false
    /// Colors the waveform to match the artwork, same as `PillPlayerView`/
    /// `ExpandedPlayerView` -- a plain white waveform read flat against
    /// the artwork-derived background here.
    @StateObject private var artworkColor = ArtworkColorLoader()

    static let collapsedSize = CGSize(width: 280, height: 72)
    /// Noticeably shorter than an earlier 200pt pass -- Atoll and
    /// QuartzNotch both keep their expanded lock-screen card tight, with
    /// the artwork nearly filling the card's height and controls sitting
    /// close together, rather than spreading thin content across a tall,
    /// mostly-empty panel.
    static let expandedSize = CGSize(width: 300, height: 148)

    private static let hoverSpring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// Fixed across both states -- see the type doc.
    private static let cardCornerRadius: CGFloat = 26

    private var artworkSize: CGFloat { isExpanded ? 60 : 40 }
    /// A steady ~0.28 ratio of `artworkSize` at both steps, not two
    /// unrelated fixed values -- keeps the artwork's own curve looking
    /// consistent as it scales, matching the concentric-shape idea above.
    private var artworkCornerRadius: CGFloat { artworkSize * 0.28 }
    private var titleFontSize: CGFloat { isExpanded ? 14 : 13 }
    private var artistFontSize: CGFloat { isExpanded ? 12 : 11 }
    private var headerSpacing: CGFloat { isExpanded ? 3 : 2 }
    private var cardSize: CGSize { isExpanded ? Self.expandedSize : Self.collapsedSize }

    var body: some View {
        Group {
            if let info = nowPlaying.current {
                content(for: info)
            } else {
                Color.clear
            }
        }
        .frame(width: Self.expandedSize.width, height: Self.expandedSize.height, alignment: .bottom)
        .onHover { hovering in
            withAnimation(Self.hoverSpring) {
                isExpanded = hovering
            }
        }
        .onAppear { artworkColor.load(from: nowPlaying.current?.artworkURL) }
        .onChange(of: nowPlaying.current?.artworkURL) { _, url in artworkColor.load(from: url) }
    }

    private func content(for info: NowPlayingInfo) -> some View {
        ZStack {
            BlurredArtworkBackground(url: info.artworkURL)

            VStack(spacing: isExpanded ? 10 : 0) {
                HStack(spacing: 10) {
                    ArtworkView(url: info.artworkURL, cornerRadius: artworkCornerRadius)
                        .frame(width: artworkSize, height: artworkSize)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .parallax3D()
                    VStack(alignment: .leading, spacing: headerSpacing) {
                        // A light text shadow, new alongside the lighter
                        // overlay above -- with less darkening behind it,
                        // title/artist need their own small assist to
                        // stay legible over brighter album art, the same
                        // way iOS's own Lock Screen text sits on a
                        // shadow/gradient rather than raw content.
                        Text(info.title)
                            .font(.system(size: titleFontSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .lineLimit(1)
                        Text(info.artist)
                            .font(.system(size: artistFontSize))
                            .foregroundStyle(.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)

                    // Only in the expanded state -- the collapsed 72pt-tall
                    // card is already tight with just artwork+text (see
                    // the type doc's note on why it stays a fixed,
                    // non-interpolated corner radius/compact size), and
                    // ExpandedPlayerView/PillPlayerView both reserve the
                    // waveform its own breathing room rather than
                    // shoehorning it into an already-cramped row.
                    if isExpanded {
                        WaveformView(
                            isPlaying: info.isPlaying,
                            color: artworkColor.color,
                            height: artworkSize * 0.6,
                            levels: audioTap.isRunning ? audioTap.levels : nil
                        )
                    }
                }

                ScrubberView(duration: info.duration, elapsed: info.elapsed, onSeek: onSeek)
                    .frame(height: isExpanded ? 18 : 0)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()

                transportRow(for: info)
                    .frame(height: isExpanded ? 26 : 0)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()
            }
            .padding(14)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }

    /// A tight, centered cluster (Atoll/QuartzNotch's own transport rows),
    /// not the full-width `Spacer`-distributed row an earlier pass used --
    /// that spread the three buttons to the card's edges with a dead gap
    /// in the middle, which read as sparse rather than compact.
    private func transportRow(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 22) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            Button(action: onPlayPause) {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// A blurred, darkened, saturated copy of the artwork filling the card --
/// see the type doc for why this replaces a flat tint or system glass.
/// Shares `ArtworkImageCache` with `ArtworkView` so the two don't each run
/// their own fetch of the same URL.
private struct BlurredArtworkBackground: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Blur raised 36->44 and the darkening overlay
                        // below dropped 0.4->0.26 per direct feedback
                        // ("more liquid glass like, more transparent
                        // ish") -- more of the artwork's own color/light
                        // reads through, which is what makes glass read
                        // as glass rather than a dark tinted panel, while
                        // staying the same "glass built from content"
                        // technique the type doc documents (not a switch
                        // to system .glassEffect(), which would be
                        // glass-on-glass over the real wallpaper this
                        // window sits above). Saturation left alone --
                        // pushing that up further alongside more
                        // transparency risked the background reading as
                        // garish rather than airy.
                        .blur(radius: 44)
                        .saturation(1.4)
                } else {
                    Color.black
                }
            }
            .overlay(Color.black.opacity(0.26))
        }
        .task(id: url) {
            image = nil
            guard let url,
                  let data = await ArtworkImageCache.shared.data(for: url),
                  let nsImage = NSImage(data: data) else { return }
            image = nsImage
        }
    }
}
