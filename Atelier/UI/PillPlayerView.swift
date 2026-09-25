import SwiftUI

/// The persistent sliver shown while `.pill` (playing, not hovering or
/// peeking). `pillSize` is only `pillExtraWidth` (68pt, see
/// `NotchController`) wider than the real notch cutout and the *same
/// height* -- no room for text, only two ~34pt flanks either side of the
/// physical camera cutout (which has no display pixels of its own, so a
/// plain `Spacer` between the two flanks correctly leaves it untouched).
/// Artwork icon on the left flank, a mini waveform on the right --
/// matches Clayton630/QuartzNotch's "real-time audio visualizer" resting
/// pill, read via `gh api` before designing this (see
/// check-reference-apps-first).
struct PillPlayerView: View {
    let info: NowPlayingInfo?
    let notchHeight: CGFloat
    @ObservedObject var audioTap: AudioTap
    @StateObject private var artworkColor = ArtworkColorLoader()

    /// Sized with real margin on every side (both vertical, via the
    /// HStack's default center alignment against the pill's fixed
    /// height, and horizontal, via the explicit leading padding below) --
    /// a second on-device tuning pass after 28pt (edge-to-edge, no
    /// breathing room) read as too large.
    private var artworkSide: CGFloat { min(notchHeight - 10, 17.5) }

    var body: some View {
        Group {
            if let info {
                HStack(spacing: 0) {
                    // ~23% of the 17.5pt side (Apple's icon squircle is ~22%).
                    // Also ~concentric with the pill's 11pt bottom corner:
                    // 11 minus the artwork's ~7-8pt inset from the bottom edge.
                    // (It used to be 6 = the pill's *top* radius, which is the
                    // flare into the menu bar and unrelated to this corner.)
                    ArtworkView(url: info.artworkURL, cornerRadius: artworkSide * 0.23)
                        .frame(width: artworkSide, height: artworkSide)

                    Spacer(minLength: 0)

                    // `WaveformView` computes its own intrinsic width from
                    // barCount/barWidth/barSpacing (18.5pt here), which
                    // isn't exactly `artworkSide` (17.5pt) -- the two
                    // flanks were reserving very slightly different layout
                    // widths, on top of the bars' own sparser visual
                    // density (thin capsules with gaps vs. a solid
                    // artwork block) reading as narrower still. Forcing an
                    // explicit, centered `artworkSide`-wide frame here
                    // makes the two flanks' *reserved* width genuinely
                    // equal -- confirmed as the real asymmetry, not the
                    // padding (13pt/13pt already symmetric).
                    WaveformView(
                        isPlaying: info.isPlaying,
                        color: artworkColor.color,
                        barWidth: 2,
                        barSpacing: 1.3,
                        height: artworkSide,
                        levels: audioTap.isRunning ? audioTap.levels : nil
                    )
                    .frame(width: artworkSide)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Now \(info.isPlaying ? "playing" : "paused"): \(info.title) by \(info.artist)")
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 13)
        .onAppear { artworkColor.load(from: info?.artworkURL) }
        .onChange(of: info?.artworkURL) { _, url in artworkColor.load(from: url) }
    }
}
