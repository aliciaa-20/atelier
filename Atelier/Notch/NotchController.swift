import AppKit
import Combine
import SwiftUI

/// Owns the notch panel's lifecycle. Per invariant 3, the panel itself is
/// sized once to the maximum expanded footprint and never resized again —
/// only the SwiftUI content inside it grows/shrinks on hover, which avoids
/// the visible jank of animating an NSWindow's frame directly.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let viewModel: NotchViewModel
    private let nowPlayingCoordinator = NowPlayingCoordinator()
    private let liveActivityCoordinator: LiveActivityCoordinator
    private var notchStateCancellable: AnyCancellable?
    private var isPlayingCancellable: AnyCancellable?
    private var trackChangeCancellable: AnyCancellable?
    private var peekDecayTask: Task<Void, Never>?

    /// The pill hugs the notch's own height but extends past its width so
    /// it reads as a deliberate sliver rather than a wider stock notch.
    private static let pillExtraWidth: CGFloat = 40

    /// Height of `ExpandedPlayerView`'s own content: artwork+text row (50)
    /// + spacing (8) + scrubber incl. time labels (22) + spacing (8) +
    /// transport row (26) + bottom padding (10). Kept compact deliberately
    /// -- an earlier, roomier pass (144/360, matching dynamicnotch's own
    /// absolute pixel sizes) opened too far down for a menu-bar-adjacent
    /// panel; this sits *below* the real notch cutout, which has no
    /// display pixels of its own, so the panel's total height must add the
    /// physical notch height on top of this.
    private static let playerContentHeight: CGFloat = 128
    private static let expandedWidth: CGFloat = 352
    /// Narrower and more compact than the full player — a single
    /// artwork(34)+text(92)+waveform(~18.5) row with 24pt horizontal
    /// padding (buffer over peeking's 14pt corner radius — see
    /// `PeekPlayerView`) needs ~169+48=217pt minimum; 222 leaves just
    /// enough slack for the flexible spacer between text and waveform.
    private static let peekWidth: CGFloat = 222
    /// `PeekPlayerView`'s own content — a single artwork+title/artist+
    /// waveform row (34, governed by the two-line text block: 16+2+16)
    /// + top/bottom padding (4+9).
    private static let peekContentHeight: CGFloat = 47
    private static let peekDuration: Duration = .seconds(2.5)

    init() {
        guard let screen = NSScreen.notchedOrMain else {
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, pillSize: .zero, peekSize: .zero)
            liveActivityCoordinator = LiveActivityCoordinator(sources: [
                NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: 0)
            ])
            panel.contentView = ClickThroughHostingView(
                rootView: NotchRootView(
                    viewModel: viewModel,
                    nowPlaying: nowPlayingCoordinator,
                    liveActivity: liveActivityCoordinator
                )
            )
            return
        }

        let metrics = ScreenMetrics(screen: screen)
        let collapsedRect = NotchGeometry.notchRect(for: metrics)
        liveActivityCoordinator = LiveActivityCoordinator(sources: [
            NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height)
        ])
        let expandedSize = CGSize(
            width: Self.expandedWidth,
            height: collapsedRect.height + Self.playerContentHeight
        )
        let pillSize = CGSize(
            width: collapsedRect.width + Self.pillExtraWidth,
            height: collapsedRect.height
        )
        let peekSize = CGSize(
            width: Self.peekWidth,
            height: collapsedRect.height + Self.peekContentHeight
        )
        viewModel = NotchViewModel(
            collapsedSize: collapsedRect.size,
            expandedSize: expandedSize,
            pillSize: pillSize,
            peekSize: peekSize
        )

        let maxRect = CGRect(
            x: collapsedRect.midX - expandedSize.width / 2,
            y: collapsedRect.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )

        panel.contentView = ClickThroughHostingView(
            rootView: NotchRootView(
                viewModel: viewModel,
                nowPlaying: nowPlayingCoordinator,
                liveActivity: liveActivityCoordinator
            )
        )
        panel.setFrame(maxRect, display: true)
        panel.orderFrontRegardless()

        // NotchController lives for the whole app run (owned by AtelierApp),
        // so this observation never needs to be torn down.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak viewModel] _ in
            Task { @MainActor in
                viewModel?.notchLandedOnNewSpace()
            }
        }

        // Faster polling while expanded/peeking keeps the scrubber smooth
        // without burning cycles scripting Spotify every 250ms while idle.
        //
        // No manual `makeKey()` call here: `NotchPanel.canBecomeKey` plus
        // `ClickThroughHostingView.acceptsFirstMouse` (ADR 0003) are enough
        // on their own — confirmed against Atoll's `DynamicIslandWindow`,
        // which never calls `makeKey()` on its notch window either (only
        // `orderFrontRegardless()`, see `DynamicIslandApp.swift`). A prior
        // version of this file called `panel?.makeKey()` on expand as a
        // workaround for a click-handling bug that was actually caused by
        // something else; keeping it around risked masking the real fix.
        notchStateCancellable = viewModel.$state.sink { [weak nowPlayingCoordinator] state in
            nowPlayingCoordinator?.setExpanded(state == .expanded || state == .peeking)
        }

        // Drives the collapsed <-> pill transition from actual playback
        // state, independent of hover. `removeDuplicates` keeps a steady
        // isPlaying value across every 1s/0.25s poll tick from feeding the
        // state machine an event it'd just no-op on.
        //
        // When peek-on-change is enabled, a play/pause toggle earns a peek
        // too (`.playbackToggled`), same as a track change — it already
        // resolves resting state (pill vs collapsed) correctly on decay via
        // `peekTimerElapsed`'s fresh `isPlaying` read, so `.isPlayingChanged`
        // only needs to run when peek is off and there's no decay to do that
        // resolution later.
        // Generalizes the old isPlaying signal to "does the stack have
        // any content at all" -- for now-playing that's still exactly
        // isPlaying, since NowPlayingLiveActivitySource only publishes
        // content while playing (Task 4). `removeDuplicates` preserves
        // the exact behavior the old `.map { isPlaying }.removeDuplicates()`
        // had: only fire on an actual true<->false transition.
        isPlayingCancellable = liveActivityCoordinator.$hasContent
            .removeDuplicates()
            .sink { [weak self] hasContent in
                guard let self else { return }
                if AtelierSettings.peekOnTrackChangeEnabled {
                    triggerPeek(with: .playbackToggled)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.handle(.isPlayingChanged(hasContent))
                    }
                }
            }

        // Peek on track change reuses our own persistent panel/state
        // machine (`.peeking`), not a second window. A DynamicNotchKit
        // popover was tried first per the v2 plan's own verification step —
        // on-device it visually overlapped our panel (its window sits at
        // `.screenSaver` level, ours at `.mainMenu + 3`) and could only show
        // a generic icon, not real artwork. Reusing `ExpandedPlayerView`
        // gets real artwork/waveform/scrubber for free and can't conflict
        // with itself. DynamicNotchKit stays a dependency for later,
        // genuinely separate activity types (timers, calendar) that aren't
        // just "a preview of what the panel already shows."
        // liveActivityCoordinator.identityChanged already dedups by
        // content id (Task 5) -- the old lastTrackKey bookkeeping lived
        // here only because that dedup didn't exist yet.
        trackChangeCancellable = liveActivityCoordinator.identityChanged
            .sink { [weak self] in
                self?.triggerPeek(with: .trackChanged)
            }

        nowPlayingCoordinator.start()
    }

    private func triggerPeek(with event: NotchEvent) {
        guard AtelierSettings.peekOnTrackChangeEnabled else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.handle(event)
        }

        // Cancel any still-pending decay from an earlier peek so a rapid
        // skip or play/pause flurry doesn't cut the new peek short.
        peekDecayTask?.cancel()
        peekDecayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration)
            guard !Task.isCancelled, let self else { return }
            let hasContent = liveActivityCoordinator.hasContent
            // Slower and more damped than the open, matching hoverEnded's
            // treatment in NotchRootView — the peek retracting at the same
            // snappy speed it opened with read as abrupt, the same problem
            // already fixed once for hover-close.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) {
                viewModel.handle(.peekTimerElapsed(isPlaying: hasContent))
            }
        }
    }
}
