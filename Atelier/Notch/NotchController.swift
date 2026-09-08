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
    /// Owned here (not just by `liveActivityCoordinator`'s source list) so
    /// `mediaKeyInterceptor` below has a stable instance to call
    /// `.step(by:)`/`.toggleMute()` on.
    private let volumeSource: VolumeSource
    private let brightnessSource: BrightnessSource
    /// Installs its `CGEventTap` on creation and tears it down on deinit --
    /// held for exactly that lifetime, same as `panel`/`viewModel`.
    private let mediaKeyInterceptor: MediaKeyInterceptor
    private var notchStateCancellable: AnyCancellable?
    private var isPlayingCancellable: AnyCancellable?
    private var trackChangeCancellable: AnyCancellable?
    private var peekDecayTask: Task<Void, Never>?

    /// The pill hugs the notch's own height but extends past its width so
    /// it reads as a deliberate sliver rather than a wider stock notch.
    /// Tuned on-device across several passes -- see `PillPlayerView`'s
    /// artwork size and left/right gap for the matching content values.
    private static let pillExtraWidth: CGFloat = 64

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
    /// Volume/Brightness's peek has no title/artist text (Phase 8) --
    /// just an icon + scrub bar, so it doesn't need `peekWidth`/
    /// `peekContentHeight`'s room for two lines of text. Real macOS's own
    /// OSD is compact for the same reason. Narrower and shorter than the
    /// shared peek size, not a separate window -- see Invariant 3's own
    /// note: the panel itself never resizes, only the SwiftUI content
    /// frame within it does, same mechanism as every other state.
    private static let compactPeekWidth: CGFloat = 210
    /// Icon+bar row (~18) + top/bottom padding (2+6), against
    /// `peekContentHeight`'s 47 (sized for two lines of text instead).
    private static let compactPeekContentHeight: CGFloat = 26
    // Not private: `VolumeSource`/`BrightnessSource` match their own
    // self-clearing decay to this exact duration -- see their own
    // `decayDuration` doc comments for why a shorter, independent timer
    // caused a visible mid-peek glitch.
    static let peekDuration: Duration = .seconds(2.5)

    init() {
        guard let screen = NSScreen.notchedOrMain else {
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, pillSize: .zero, peekSize: .zero, compactPeekSize: .zero)
            let hudOrder = SystemHUDOrder()
            let volumeSource = VolumeSource(notchHeight: 0, hudOrder: hudOrder)
            let brightnessSource = BrightnessSource(notchHeight: 0, hudOrder: hudOrder)
            self.volumeSource = volumeSource
            self.brightnessSource = brightnessSource
            mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
            liveActivityCoordinator = LiveActivityCoordinator(sources: [
                NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: 0),
                BatterySource(notchHeight: 0),
                volumeSource,
                brightnessSource
                // AirPodsSource intentionally not registered -- see the
                // comment at the other call site below.
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
        // AirPodsSource is not registered here on purpose (temporarily):
        // IOBluetoothDevice.register(forConnectNotifications:) crashes
        // this process 100% of the time on-device (EXC_BREAKPOINT deep
        // inside Apple's own CoreBluetooth bridge --
        // -[CBPeripheral initWithCentralManager:info:], reached via
        // IOBluetoothRegisterForNotifications enumerating already-paired
        // devices). Confirmed independent of call timing (deferring via
        // DispatchQueue.main.async made no difference) and independent of
        // a missing NSBluetoothAlwaysUsageDescription (added to
        // Info.plist, made no difference either) -- this is a real bug in
        // Apple's framework on this machine's current macOS build, not
        // something fixable from Swift. Re-enable once a workaround or an
        // OS update resolves it; see docs/ROADMAP.md's Phase 6 notes.
        let hudOrder = SystemHUDOrder()
        let volumeSource = VolumeSource(notchHeight: collapsedRect.height, hudOrder: hudOrder)
        let brightnessSource = BrightnessSource(notchHeight: collapsedRect.height, hudOrder: hudOrder)
        self.volumeSource = volumeSource
        self.brightnessSource = brightnessSource
        mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
        liveActivityCoordinator = LiveActivityCoordinator(sources: [
            NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height),
            BatterySource(notchHeight: collapsedRect.height),
            volumeSource,
            brightnessSource
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
        let compactPeekSize = CGSize(
            width: Self.compactPeekWidth,
            height: collapsedRect.height + Self.compactPeekContentHeight
        )
        viewModel = NotchViewModel(
            collapsedSize: collapsedRect.size,
            expandedSize: expandedSize,
            pillSize: pillSize,
            peekSize: peekSize,
            compactPeekSize: compactPeekSize
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
                // Only peek-worthy content (peeksOnChange == true, the
                // default -- false for ambient content like Battery)
                // earns the pop-out peek; `nil` on departure (`?? false`)
                // also means going to no-content never peeks either, so
                // an ambient-only pill doesn't flash a peek on its way
                // down to collapsed.
                let shouldPeek = AtelierSettings.peekOnTrackChangeEnabled
                    && (liveActivityCoordinator.topContent?.peeksOnChange ?? false)
                if shouldPeek {
                    triggerPeek(with: .playbackToggled)
                } else {
                    withAnimation(NotchAnimations.open) {
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
        // here only because that dedup didn't exist yet. The coordinator's
        // dedup id survives a pause/resume of the same track (it's only
        // ever updated to a non-nil id, never cleared when content
        // disappears), so it does not spuriously re-fire on resume --
        // matching lastTrackKey's own behavior, which was likewise
        // untouched by isPlaying transitions.
        trackChangeCancellable = liveActivityCoordinator.identityChanged
            .sink { [weak self] in
                self?.triggerPeek(with: .trackChanged)
            }

        nowPlayingCoordinator.start()
    }

    private func triggerPeek(with event: NotchEvent) {
        guard AtelierSettings.peekOnTrackChangeEnabled else { return }
        // Reuses the exact same curves as hovering (`NotchRootView`'s
        // `onHover`), not separate peek-only constants -- a peek is the
        // same open/close motion as hover, just triggered a different way.
        // Confirmed on-device: dedicated `peekOpen`/`peekClose` values
        // (0.8/0.92 damping vs. `open`/`close`'s 0.65/0.92) read as a
        // visibly less smooth, inconsistent close compared to hovering.
        withAnimation(NotchAnimations.open) {
            viewModel.handle(event)
        }

        // Cancel any still-pending decay from an earlier peek so a rapid
        // skip or play/pause flurry doesn't cut the new peek short.
        peekDecayTask?.cancel()
        peekDecayTask = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration)
            guard !Task.isCancelled, let self else { return }
            let hasContent = liveActivityCoordinator.hasContent
            withAnimation(NotchAnimations.close) {
                viewModel.handle(.peekTimerElapsed(isPlaying: hasContent))
            }
        }
    }
}
