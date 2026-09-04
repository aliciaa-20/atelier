import CoreAudio
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @StateObject private var artworkColor = ArtworkColorLoader()
    @State private var settleScale: CGFloat = 1
    @State private var outputDevices: [AudioOutputDevice] = []
    @State private var currentOutputDeviceID: AudioDeviceID?

    /// Small/sharp notch-cutout radii at rest, softer/rounder-card radii
    /// once expanded -- matching jackson-storm/dynamicnotch's own
    /// distinction between its collapsed notch shape (~9/13) and its
    /// expanded card shape (34/44, much closer to equal) rather than
    /// reusing one small radius pair at every size.
    ///
    /// `.peeking` gets its own equal top/bottom radius rather than
    /// reusing `.expanded`'s 14/20 — at the peek pill's small, compact
    /// size, mismatched radii read as an inconsistent shape rather than
    /// one cohesive rounded card (design feedback after seeing it
    /// on-device).
    private var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        switch viewModel.state {
        case .collapsed, .pill:
            (top: 6, bottom: 14)
        case .expanded:
            (top: 14, bottom: 20)
        case .peeking:
            (top: 14, bottom: 14)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom)
                    .fill(Color.black)

                if viewModel.state == .expanded {
                    ExpandedPlayerView(
                        info: nowPlaying.current,
                        notchHeight: viewModel.collapsedSize.height,
                        waveformColor: artworkColor.color,
                        outputDevices: outputDevices,
                        currentOutputDeviceID: currentOutputDeviceID,
                        onPlayPause: { Task { await nowPlaying.playPause() } },
                        onNext: { Task { await nowPlaying.next() } },
                        onPrevious: { Task { await nowPlaying.previous() } },
                        onSeek: { time in Task { await nowPlaying.seek(to: time) } },
                        onToggleShuffle: { Task { await nowPlaying.toggleShuffle() } },
                        onSelectOutputDevice: { deviceID in
                            OutputDeviceManager.setDefaultOutputDevice(deviceID)
                            currentOutputDeviceID = deviceID
                        }
                    )
                    .transition(.opacity)
                    .onAppear {
                        outputDevices = OutputDeviceManager.availableOutputDevices()
                        currentOutputDeviceID = OutputDeviceManager.currentDefaultOutputDevice()
                    }
                } else if viewModel.state == .peeking {
                    PeekPlayerView(
                        info: nowPlaying.current,
                        notchHeight: viewModel.collapsedSize.height,
                        waveformColor: artworkColor.color
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: viewModel.currentSize.width, height: viewModel.currentSize.height)
            .clipShape(NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom))
            .scaleEffect(settleScale, anchor: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.handle(.hoverStarted)
                    }
                } else {
                    // Slower and more damped than the open — closing snapped
                    // shut at the same speed it opened, which read as
                    // abrupt since there's no destination content to draw
                    // the eye the way the expanding player does on open.
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
                        viewModel.handle(.hoverEnded(isPlaying: nowPlaying.current?.isPlaying ?? false))
                    }
                }
            }
            // `allowsHitTesting(false)` must sit on the Spacer alone, not on
            // this whole VStack — an ancestor's `false` overrides a
            // descendant's `true`, so applying it any higher up would (and
            // did) silently swallow every click/hover in the notch/player
            // region above, no matter what this ZStack sets on itself.
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.spaceChangeTick) { _, _ in
            playSettleAnimation()
        }
        .onChange(of: nowPlaying.current?.artworkURL) { _, url in
            artworkColor.load(from: url)
        }
    }

    /// A quick tuck-and-spring-back when landing on a new Space, so the
    /// notch staying fixed through the swipe (unavoidable — see
    /// `NotchViewModel.spaceChangeTick`) reads as an intentional arrival cue
    /// rather than an accidental float.
    private func playSettleAnimation() {
        withAnimation(.easeOut(duration: 0.12)) {
            settleScale = 0.55
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.12)) {
            settleScale = 1
        }
    }
}
