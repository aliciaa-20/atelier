import SwiftUI

/// Atelier's own now-playing card for the lock screen (see the design
/// spec) -- collapsed by default (artwork + title/artist, with parallax),
/// expands on hover to a larger view with a real scrubber and transport
/// controls. Local `@State`, not `NotchStateMachine` -- this window is
/// entirely separate from the notch. Observes `NowPlayingCoordinator`
/// directly (not a snapshot `NowPlayingInfo`) so the card stays live for
/// as long as the window exists, the same way any other SwiftUI subtree
/// reacts to a `@Published` change.
struct LockScreenMusicCardView: View {
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isExpanded = false

    static let collapsedSize = CGSize(width: 280, height: 72)
    static let expandedSize = CGSize(width: 340, height: 200)

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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded = hovering
            }
        }
    }

    @ViewBuilder
    private func content(for info: NowPlayingInfo) -> some View {
        Group {
            if isExpanded {
                expandedContent(for: info)
                    .frame(width: Self.expandedSize.width, height: Self.expandedSize.height)
            } else {
                collapsedContent(for: info)
                    .frame(width: Self.collapsedSize.width, height: Self.collapsedSize.height)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }

    private func collapsedContent(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: info.artworkURL, cornerRadius: 12)
                .frame(width: 40, height: 40)
                .parallax3D()
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(info.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func expandedContent(for info: NowPlayingInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkView(url: info.artworkURL, cornerRadius: 12)
                    .frame(width: 64, height: 64)
                    .parallax3D()
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ScrubberView(duration: info.duration, elapsed: info.elapsed, onSeek: onSeek)
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
}
