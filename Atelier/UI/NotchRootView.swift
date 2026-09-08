import CoreAudio
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @ObservedObject var liveActivity: LiveActivityCoordinator
    @StateObject private var artworkColor = ArtworkColorLoader()
    @State private var settleScale: CGFloat = 1
    @State private var outputDevices: [AudioOutputDevice] = []
    @State private var currentOutputDeviceID: AudioDeviceID?
    /// The last real `liveActivity.topContent` seen, kept around so the
    /// `.peeking` branch has something to render even if the source has
    /// already withdrawn its content (e.g. `BatterySource`'s "Charging"
    /// state, which decays after one poll) while the 2.5s peek animation
    /// is still playing out. Not cleared on retract -- see Fix 3 in the
    /// final review pass.
    @State private var lastPeekContent: LiveActivityContent?

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
                    if let topContent = liveActivity.topContent ?? lastPeekContent {
                        topContent.peekView()
                            .transition(.opacity)
                    }
                } else if viewModel.state == .pill {
                    // interruptContent (e.g. Battery briefly surfacing
                    // over music) wins while it's set; otherwise the real
                    // top content shows as usual.
                    if let content = liveActivity.interruptContent ?? liveActivity.topContent {
                        content.pillView()
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: viewModel.currentSize.width, height: viewModel.currentSize.height)
            .clipShape(NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom))
            .scaleEffect(settleScale, anchor: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    // A non-expandable live activity on top (Volume,
                    // Brightness, Battery) has no expanded view of its
                    // own -- `.hoverStarted` would still force open
                    // `ExpandedPlayerView`, showing now-playing info
                    // unrelated to what's actually peeking (the same gap
                    // Phase 6 accepted and deferred, now surfaced for
                    // real by Phase 8's peeks). `nil` topContent (nothing
                    // peeking right now) keeps the original hover-to-open
                    // behavior for the plain notch/pill.
                    if liveActivity.topContent?.isExpandable == false {
                        withAnimation(NotchAnimations.close) {
                            viewModel.handle(.peekTimerElapsed(isPlaying: liveActivity.hasContent))
                        }
                    } else {
                        withAnimation(NotchAnimations.open) {
                            viewModel.handle(.hoverStarted)
                        }
                    }
                } else {
                    // Slower and more damped than the open — closing snapped
                    // shut at the same speed it opened, which read as
                    // abrupt since there's no destination content to draw
                    // the eye the way the expanding player does on open.
                    withAnimation(NotchAnimations.close) {
                        viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                    }
                }
            }
            // Always wired with the real capabilities/closures — the
            // enabled/disabled gate lives solely in
            // `NotchGestureModifier`'s own `handleScroll`, which reads
            // `AtelierSettings.gesturesEnabled` fresh on every scroll
            // event. A ternary here that swapped in an inert modifier
            // when the setting was off double-gated on a value SwiftUI
            // doesn't observe (`UserDefaults`, not `@Published`), so
            // toggling the setting back on could leave the inert
            // modifier in place until an unrelated re-render happened to
            // sweep it away.
            .modifier(
                NotchGestureModifier(
                    capabilities: NotchGestureCapabilities(
                        canOpen: viewModel.state == .collapsed || viewModel.state == .pill,
                        canClose: viewModel.state == .expanded || viewModel.state == .peeking,
                        canSkip: liveActivity.topContent?.isExpandable == true
                    ),
                    onOpen: {
                        withAnimation(NotchAnimations.open) {
                            viewModel.handle(.hoverStarted)
                        }
                    },
                    onClose: {
                        withAnimation(NotchAnimations.close) {
                            viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                        }
                    },
                    onSkipForward: {
                        Task { await nowPlaying.next() }
                    },
                    onSkipBackward: {
                        Task { await nowPlaying.previous() }
                    }
                )
            )
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
        .onChange(of: liveActivity.topContent?.id) { _, _ in
            if let topContent = liveActivity.topContent {
                lastPeekContent = topContent
            }
        }
    }

    /// A quick tuck-and-spring-back when landing on a new Space, so the
    /// notch staying fixed through the swipe (unavoidable — see
    /// `NotchViewModel.spaceChangeTick`) reads as an intentional arrival cue
    /// rather than an accidental float.
    private func playSettleAnimation() {
        withAnimation(NotchAnimations.settleTuck) {
            settleScale = 0.55
        }
        withAnimation(NotchAnimations.settleSpringBack.delay(0.12)) {
            settleScale = 1
        }
    }
}
