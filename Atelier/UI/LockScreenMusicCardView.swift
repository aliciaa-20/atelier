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
        VStack(spacing: isExpanded ? 14 : 0) {
            HStack(spacing: 12) {
                ArtworkView(url: info.artworkURL, cornerRadius: artworkCornerRadius)
                    .frame(width: artworkSize, height: artworkSize)
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
                .frame(height: isExpanded ? 14 : 0)
                .opacity(isExpanded ? 1 : 0)
                .clipped()

            transportRow(for: info)
                .frame(height: isExpanded ? 26 : 0)
                .opacity(isExpanded ? 1 : 0)
                .clipped()
        }
        .padding(16)
        .frame(width: cardSize.width, height: cardSize.height)
        // Real Liquid Glass (`.glassEffect`), not a flat tinted rectangle --
        // Atoll's `LockScreenMusicPanel` uses the same material family
        // (`.ultraThinMaterial`/liquid glass) so the card reads correctly
        // over an arbitrary wallpaper instead of looking like a dark box.
        .glassEffect(in: .rect(cornerRadius: cardCornerRadius))
    }

    private func transportRow(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 28) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
            }
            Button(action: onPlayPause) {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
            }
            Button(action: onNext) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
