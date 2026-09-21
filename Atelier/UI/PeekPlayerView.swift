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
    @ObservedObject var audioTap: AudioTap
    @StateObject private var artworkColor = ArtworkColorLoader()

    var body: some View {
        Group {
            if let info {
                content(for: info)
            }
        }
        // NotchShape's vertical edges are inset by `topCornerRadius`
        // (flat, for their whole height) then curve further inward near
        // the very bottom by up to `bottomCornerRadius` more (see
        // NotchShape.swift) — but that curve is a quadratic Bezier whose
        // control point pulls it mostly *vertical* at first, so the extra
        // inset stays small until content gets close to the true bottom
        // edge. Peeking uses equal 14/14 radii (see NotchRootView) for a
        // cohesive rounded-card look, so the flat-zone inset is 14pt —
        // horizontal padding needs real buffer over that.
        .padding(.horizontal, 24)
        .padding(.bottom, 9)
        .padding(.top, notchHeight + 4)
        .onAppear { artworkColor.load(from: info?.artworkURL) }
        .onChange(of: info?.artworkURL) { _, url in artworkColor.load(from: url) }
    }

    private func content(for info: NowPlayingInfo) -> some View {
        HStack(spacing: 8) {
            // A smaller radius than ExpandedPlayerView's default (8) —
            // Peek's panel corner (14, see NotchRootView) is large
            // relative to this 34pt square, so the artwork's own rounding
            // needs to be more subtle to read as concentric with it
            // rather than competing with a second, differently-scaled
            // rounded shape right next to it.
            ArtworkView(url: info.artworkURL, cornerRadius: 5)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: info.title, font: .headline, color: .white, width: 92, height: 16)
                MarqueeText(text: info.artist, font: .subheadline, color: .white.opacity(0.65), width: 92, height: 16)
            }

            Spacer(minLength: 0)

            WaveformView(
                isPlaying: info.isPlaying,
                color: artworkColor.color,
                barWidth: 2,
                barSpacing: 1.3,
                height: 14,
                levels: audioTap.isRunning ? audioTap.levels : nil
            )
        }
    }
}
