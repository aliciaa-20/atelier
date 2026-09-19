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
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isExpanded = false

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
                        Text(info.title)
                            .font(.system(size: titleFontSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(info.artist)
                            .font(.system(size: artistFontSize))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
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
                        .blur(radius: 36)
                        .saturation(1.4)
                } else {
                    Color.black
                }
            }
            .overlay(Color.black.opacity(0.4))
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
