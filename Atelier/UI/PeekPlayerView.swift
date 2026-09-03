import SwiftUI

/// The compact view shown while `.peeking` (auto-shown on a track change,
/// not hover-driven) — deliberately not `ExpandedPlayerView`: no transport
/// controls or scrubber, just enough to notice the song changed. Artwork on
/// the left, title/artist stacked in the middle, waveform on the right.
struct PeekPlayerView: View {
    let info: NowPlayingInfo?
    /// Same reasoning as `ExpandedPlayerView`: the real notch cutout has no
    /// display pixels of its own, so content starts below it.
    let notchHeight: CGFloat
    let waveformColor: Color

    var body: some View {
        Group {
            if let info {
                content(for: info)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, notchHeight + 10)
    }

    private func content(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: info.artworkURL)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info.title, font: .headline, color: .white, width: 110)
                Text(info.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            WaveformView(isPlaying: info.isPlaying, color: waveformColor)
        }
    }
}
