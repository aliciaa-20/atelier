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
    private var notchStateCancellable: AnyCancellable?
    private var isPlayingCancellable: AnyCancellable?
    private var trackChangeCancellable: AnyCancellable?
    private var lastTrackKey: String?
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
    /// Narrower than the full player — a single artwork+text+waveform row
    /// doesn't need as much horizontal room as artwork+text+transport row.
    /// Widened twice now -- 260 and then 290 both still ran the actual
    /// content (artwork + marquee column + waveform + spacing + padding)
    /// right up against the edge instead of leaving real margin. This
    /// value now has a genuine buffer, not just enough to exactly fit.
    private static let peekWidth: CGFloat = 320
    /// `PeekPlayerView`'s own content — a single artwork+title/artist+
    /// waveform row (40) + top/bottom padding (10+12), no scrubber or
    /// transport row.
    private static let peekContentHeight: CGFloat = 62
    private static let peekDuration: Duration = .seconds(2.5)

    init() {
        guard let screen = NSScreen.notchedOrMain else {
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, pillSize: .zero, peekSize: .zero)
            panel.contentView = ClickThroughHostingView(
                rootView: NotchRootView(viewModel: viewModel, nowPlaying: nowPlayingCoordinator)
            )
            return
        }

        let metrics = ScreenMetrics(screen: screen)
        let collapsedRect = NotchGeometry.notchRect(for: metrics)
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
            rootView: NotchRootView(viewModel: viewModel, nowPlaying: nowPlayingCoordinator)
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
        isPlayingCancellable = nowPlayingCoordinator.$current
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak viewModel] isPlaying in
                viewModel?.handle(.isPlayingChanged(isPlaying))
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
        trackChangeCancellable = nowPlayingCoordinator.$current
            .compactMap { $0 }
            .sink { [weak self] info in
                let key = "\(info.title)|\(info.artist)"
                guard key != self?.lastTrackKey else { return }
                self?.lastTrackKey = key
                self?.handleTrackChange()
            }

        nowPlayingCoordinator.start()
    }

    private func handleTrackChange() {
        guard AtelierSettings.peekOnTrackChangeEnabled else { return }
        viewModel.handle(.trackChanged)

        // Cancel any still-pending decay from an earlier track change so a
        // rapid skip doesn't cut the new peek short.
        peekDecayTask?.cancel()
        peekDecayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration)
            guard !Task.isCancelled, let self else { return }
            let isPlaying = nowPlayingCoordinator.current?.isPlaying ?? false
            viewModel.handle(.peekTimerElapsed(isPlaying: isPlaying))
        }
    }
}
