import SwiftUI

/// The persistent sliver shown while `.pill` (playing, not hovering or
/// peeking). `pillSize` is only `pillExtraWidth` (40pt, see
/// `NotchController`) wider than the real notch cutout and the *same
/// height* -- no room for text, only two ~20pt flanks either side of the
/// physical camera cutout (which has no display pixels of its own, so a
/// plain `Spacer` between the two flanks correctly leaves it untouched).
/// Artwork icon on the left flank, a mini waveform on the right --
/// matches Clayton630/QuartzNotch's "real-time audio visualizer" resting
/// pill, read via `gh api` before designing this (see
/// check-reference-apps-first).
struct PillPlayerView: View {
    let info: NowPlayingInfo?
    let notchHeight: CGFloat
    @StateObject private var artworkColor = ArtworkColorLoader()

    private var artworkSide: CGFloat { min(notchHeight - 6, 20) }

    var body: some View {
        Group {
            if let info {
                HStack(spacing: 0) {
                    ArtworkView(url: info.artworkURL, cornerRadius: 4)
                        .frame(width: artworkSide, height: artworkSide)

                    Spacer(minLength: 0)

                    WaveformView(
                        isPlaying: info.isPlaying,
                        color: artworkColor.color,
                        barWidth: 1.5,
                        barSpacing: 1,
                        height: 12
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .onAppear { artworkColor.load(from: info?.artworkURL) }
        .onChange(of: info?.artworkURL) { _, url in artworkColor.load(from: url) }
    }
}
