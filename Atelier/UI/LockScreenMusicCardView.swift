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
/// subtrees (a plain HStack vs. a whole different VStack), which SwiftUI
/// animates as a remove-then-insert rather than a smooth resize -- that's
/// what read as "not smooth". Keeping one tree and only animating its
/// sizes/spacing/opacity is what makes Atoll's hover morph, and iOS's own
/// Lock Screen widget expansion, read as one continuous motion.
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
    static let expandedSize = CGSize(width: 340, height: 200)

    private static let hoverSpring = Animation.spring(response: 0.45, dampingFraction: 0.85)

    private var artworkSize: CGFloat { isExpanded ? 64 : 40 }
    private var artworkCornerRadius: CGFloat { isExpanded ? 18 : 12 }
    private var titleFontSize: CGFloat { isExpanded ? 15 : 13 }
    private var artistFontSize: CGFloat { isExpanded ? 12 : 11 }
    private var headerSpacing: CGFloat { isExpanded ? 4 : 2 }
    private var cardCornerRadius: CGFloat { isExpanded ? 30 : 24 }
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

            VStack(spacing: isExpanded ? 16 : 0) {
                HStack(spacing: 12) {
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
                    .frame(height: isExpanded ? 16 : 0)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()

                transportRow(for: info)
                    .frame(height: isExpanded ? 32 : 0)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()
            }
            .padding(16)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }

    /// Evenly distributed across the full card width (`Spacer()` on both
    /// ends and between each control), matching the Lock Screen/Control
    /// Center transport row rather than a tight cluster with fixed gaps --
    /// a fixed-spacing `HStack` reads as a widget bolted onto a corner
    /// instead of a control row that owns the space it's given.
    /// Prev/next sit one full step down from play/pause on both size and
    /// weight -- deliberate, not the previous version's bug where they had
    /// no explicit font size at all and fell back to the system default.
    private func transportRow(for info: NowPlayingInfo) -> some View {
        HStack {
            Spacer()
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            Button(action: onPlayPause) {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            Spacer()
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
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
