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
    private var settingsObserver: NSObjectProtocol?
    private let viewModel: NotchViewModel
    private let nowPlayingCoordinator = NowPlayingCoordinator()
    private let liveActivityCoordinator: LiveActivityCoordinator
    private let shelfStore: ShelfStore
    /// Owned here (not just by `liveActivityCoordinator`'s source list) so
    /// `mediaKeyInterceptor` below has a stable instance to call
    /// `.step(by:)`/`.toggleMute()` on.
    private let volumeSource: VolumeSource
    private let brightnessSource: BrightnessSource
    private let batterySource: BatterySource
    /// Owned here, not just by `liveActivityCoordinator`'s source list, so
    /// `NotchRootView` has a stable instance to bind `NotchPage.systemMonitor`'s
    /// tab content to -- same reasoning as `batterySource` above.
    private let systemMonitorSource: SystemMonitorSource
    /// Owned here so `NotchRootView` has a stable instance for the Calendar tab.
    private let calendarSource = CalendarSource()
    /// Owned here so the Calendar week strip and idle Home share one cache.
    private let weatherSource = WeatherSource()
    /// Owned here so `pickColor()` below has a stable instance to call
    /// `.pick()` on -- same reasoning as `volumeSource`.
    private let colorPickerSource: ColorPickerSource
    /// Installs its `CGEventTap` on creation and tears it down on deinit --
    /// held for exactly that lifetime, same as `panel`/`viewModel`.
    private let mediaKeyInterceptor: MediaKeyInterceptor
    private let lockScreenManager: LockScreenManager
    private let lockScreenPanelController: LockScreenPanelController
    private let audioTap = AudioTap()
    private var notchStateCancellable: AnyCancellable?
    private var isPlayingCancellable: AnyCancellable?
    private var trackChangeCancellable: AnyCancellable?
    private var audioTapCancellable: AnyCancellable?
    private var peekDecayTask: Task<Void, Never>?

    /// The pill hugs the notch's own height but extends past its width so
    /// it reads as a deliberate sliver rather than a wider stock notch.
    /// Tuned on-device across several passes -- see `PillPlayerView`'s
    /// artwork size and left/right gap for the matching content values.
    private static let pillExtraWidth: CGFloat = 64

    /// Height of the `.expanded` content: the `NotchTabBar` row (its top
    /// padding plus its own intrinsic height) plus `ExpandedPlayerView`'s
    /// own content -- artwork+text row (44) + spacing (4) + scrubber incl.
    /// time labels (12) + spacing (4) + transport row (~26) + top/bottom
    /// padding (6+16). Raised from 126 after the buttons were bumped back
    /// up slightly and the bottom padding widened per direct feedback
    /// ("too close to the edges" / buttons needed to sit up off the
    /// bottom) -- a starting point, like every other size in this file,
    /// pending on-device confirmation.
    private static let playerContentHeight: CGFloat = 134
    /// Idle Home (now just date/time -- battery was dropped, see
    /// `IdleHomeView`'s own doc comment) needs far less room than a real
    /// player. At 76 the content (time+date+top/bottom padding) left a lot
    /// of margin -- shrunk to match `IdleHomeView`'s own smaller time font
    /// (22->18) so the card reads as compact rather than mostly empty.
    private static let idleHomeContentHeight: CGFloat = 56
    /// Narrower than `expandedWidth` for the same reason -- a short
    /// time/date block doesn't need the full player's width.
    private static let idleHomeWidth: CGFloat = 215
    /// Narrowed from 352 alongside `ExpandedPlayerView`'s own smaller
    /// artwork/text-column trim (44pt artwork, 150pt text column) -- the
    /// wider value was sized for the previous, larger header.
    private static let expandedWidth: CGFloat = 320
    /// A single row of ~64pt item cells plus padding -- matches
    /// `ShelfView`'s own column width. Shorter than `playerContentHeight`
    /// since there's no scrubber/transport row.
    private static let shelfContentHeight: CGFloat = 90
    /// Tallest the Calendar page gets (`NotchLayout.calendarMaxRows` events);
    /// `NotchRootView` shrinks below this for emptier days.
    private static let calendarContentHeight = NotchLayout.calendarContentHeight(eventCount: NotchLayout.calendarMaxRows)
    /// Extra width added on top of the real, measured notch width
    /// (`collapsedRect.width`, from `NotchGeometry.notchRect` -- 185pt on
    /// the Atelier MacBook, see `NotchGeometryTests`), not a standalone
    /// fixed width -- matches `pillExtraWidth`'s own approach. A fixed
    /// `peekWidth` literal (218, picked without reference to the real
    /// notch) was the actual cause of the peek pill not lining up flush
    /// with the notch's own edges/corners on-device (photo evidence): it
    /// happened to be close to `collapsedRect.width + 33` on this specific
    /// display, but nothing tied it there, so any drift in the two numbers
    /// showed up as a visible gap. Deriving it from the real notch width
    /// the same way the pill already does is what actually guarantees the
    /// edges match, on this machine or any other.
    private static let peekExtraWidth: CGFloat = 19.2
    /// `PeekPlayerView`'s own content — a single artwork+title/artist+
    /// waveform row (34, governed by the two-line text block: 16+2+16)
    /// + top/bottom padding (4+9).
    private static let peekContentHeight: CGFloat = 46.4
    /// Volume/Brightness's peek has no title/artist text (Phase 8) --
    /// just an icon + scrub bar, so it doesn't need `peekExtraWidth`/
    /// `peekContentHeight`'s room for two lines of text. Real macOS's own
    /// OSD is compact for the same reason. Narrower and shorter than the
    /// shared peek size, not a separate window -- see Invariant 3's own
    /// note: the panel itself never resizes, only the SwiftUI content
    /// frame within it does, same mechanism as every other state. Same
    /// notch-relative reasoning as `peekExtraWidth` above.
    private static let compactPeekExtraWidth: CGFloat = 13.2
    /// Icon+bar row (~18) + top/bottom padding (2+6), against
    /// `peekContentHeight`'s 47 (sized for two lines of text instead).
    private static let compactPeekContentHeight: CGFloat = 25.4
    // Not private: `VolumeSource`/`BrightnessSource` match their own
    // self-clearing decay to this exact duration -- see their own
    // `decayDuration` doc comments for why a shorter, independent timer
    // caused a visible mid-peek glitch.
    static let peekDuration: Duration = .seconds(2.5)

    /// Settings that take effect on the panel itself, applied at launch and
    /// again whenever any default changes (cheap and idempotent).
    /// `.none` hides the panel from screen sharing and recording; `.readOnly`
    /// is `NSWindow`'s normal default.
    private func applyLiveSettings() {
        panel.sharingType = AtelierSettings.ghostModeEnabled ? .none : .readOnly

        // Disabling the tab mid-play must not leave hold-open keeping the
        // notch up with no way to pause.
        if !AtelierSettings.teleprompterEnabled { TeleprompterModel.shared.pause() }

        // Voice sync: the setting is the persisted preference, the model owns
        // the effective state (it flips the setting back off if permission or
        // the recognizer isn't available). No-op when they already agree.
        if AtelierSettings.teleprompterEnabled {
            Task { await TeleprompterModel.shared.setVoiceSync(AtelierSettings.teleprompterVoiceSync) }
        }

        if AtelierSettings.teleprompterEnabled, AtelierSettings.teleprompterHotkeysEnabled {
            GlobalHotkeys.shared.register { [weak self] action in self?.handleHotkey(action) }
        } else {
            GlobalHotkeys.shared.unregister()
        }
    }

    private func handleHotkey(_ action: GlobalHotkeys.Action) {
        let model = TeleprompterModel.shared
        switch action {
        case .playPause:
            // Nothing to play: don't open the notch for it (nothing would
            // retract it, since `wantsNotchOpen` never changes).
            guard model.canPlay else { return }
            // Open the notch on the Teleprompter tab first, so pressing the
            // key with the notch collapsed is visible. Opening resets the
            // page to the first tab, so select ours *after* it opens.
            if viewModel.state != .expanded {
                withAnimation(NotchAnimations.open) { viewModel.handle(.hoverStarted) }
            }
            // E.g. mid file-drag the notch stays in `.shelf`: nothing would be
            // visible, so don't start playback behind it.
            guard viewModel.state == .expanded else { return }
            viewModel.selectPage(.teleprompter)
            model.toggle()
        case .faster:
            model.stepWPM(by: 10)
        case .slower:
            model.stepWPM(by: -10)
        }
    }

    init() {
        let shelfRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atelier", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        shelfStore = ShelfStore(rootDirectory: shelfRoot)
        shelfStore.sweepExpired()

        guard let screen = NSScreen.notchedOrMain else {
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero, idleHomeSize: .zero, pillSize: .zero, peekSize: .zero, compactPeekSize: .zero, shelfSize: .zero, calendarSize: .zero, teleprompterSize: .zero)
            let hudOrder = SystemHUDOrder()
            let volumeSource = VolumeSource(notchHeight: 0, hudOrder: hudOrder)
            let brightnessSource = BrightnessSource(notchHeight: 0, hudOrder: hudOrder)
            let batterySource = BatterySource(notchHeight: 0)
            let systemMonitorSource = SystemMonitorSource(notchHeight: 0)
            let colorPickerSource = ColorPickerSource(notchHeight: 0)
            self.volumeSource = volumeSource
            self.brightnessSource = brightnessSource
            self.batterySource = batterySource
            self.systemMonitorSource = systemMonitorSource
            self.colorPickerSource = colorPickerSource
            let lockScreenManager = LockScreenManager()
            self.lockScreenManager = lockScreenManager
            self.lockScreenPanelController = LockScreenPanelController(
                nowPlayingCoordinator: nowPlayingCoordinator,
                lockScreenManager: lockScreenManager,
                audioTap: audioTap
            )
            mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
            liveActivityCoordinator = LiveActivityCoordinator(sources: [
                NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: 0, audioTap: audioTap),
                batterySource,
                ScreenRecordingSource(notchHeight: 0),
                colorPickerSource,
                volumeSource,
                brightnessSource,
                systemMonitorSource
                // AirPodsSource intentionally not registered -- see the
                // comment at the other call site below.
            ])
            panel.contentView = ClickThroughHostingView(
                rootView: NotchRootView(
                    viewModel: viewModel,
                    nowPlaying: nowPlayingCoordinator,
                    liveActivity: liveActivityCoordinator,
                    audioTap: audioTap,
                    shelfStore: shelfStore,
                    systemMonitor: systemMonitorSource,
                    calendar: calendarSource,
                    weather: weatherSource
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
        let batterySource = BatterySource(notchHeight: collapsedRect.height)
        let systemMonitorSource = SystemMonitorSource(notchHeight: collapsedRect.height)
        let colorPickerSource = ColorPickerSource(notchHeight: collapsedRect.height)
        self.volumeSource = volumeSource
        self.brightnessSource = brightnessSource
        self.batterySource = batterySource
        self.systemMonitorSource = systemMonitorSource
        self.colorPickerSource = colorPickerSource
        let lockScreenManager = LockScreenManager()
        self.lockScreenManager = lockScreenManager
        self.lockScreenPanelController = LockScreenPanelController(
            nowPlayingCoordinator: nowPlayingCoordinator,
            lockScreenManager: lockScreenManager,
            audioTap: audioTap
        )
        mediaKeyInterceptor = MediaKeyInterceptor(volumeSource: volumeSource, brightnessSource: brightnessSource)
        liveActivityCoordinator = LiveActivityCoordinator(sources: [
            NowPlayingLiveActivitySource(coordinator: nowPlayingCoordinator, notchHeight: collapsedRect.height, audioTap: audioTap),
            batterySource,
            ScreenRecordingSource(notchHeight: collapsedRect.height),
            colorPickerSource,
            volumeSource,
            brightnessSource,
            systemMonitorSource
        ])
        let expandedSize = CGSize(
            width: Self.expandedWidth,
            height: collapsedRect.height + Self.playerContentHeight
        )
        let idleHomeSize = CGSize(
            width: Self.idleHomeWidth,
            height: collapsedRect.height + Self.idleHomeContentHeight
        )
        let pillSize = CGSize(
            width: collapsedRect.width + Self.pillExtraWidth,
            height: collapsedRect.height
        )
        let peekSize = CGSize(
            width: collapsedRect.width + Self.peekExtraWidth,
            height: collapsedRect.height + Self.peekContentHeight
        )
        let compactPeekSize = CGSize(
            width: collapsedRect.width + Self.compactPeekExtraWidth,
            height: collapsedRect.height + Self.compactPeekContentHeight
        )
        let shelfSize = CGSize(
            width: Self.expandedWidth,
            height: collapsedRect.height + Self.shelfContentHeight
        )
        let calendarSize = CGSize(
            width: Self.expandedWidth,
            height: collapsedRect.height + Self.calendarContentHeight
        )
        let teleprompterSize = CGSize(
            width: NotchLayout.teleprompterWidth,
            height: NotchLayout.teleprompterHeight
        )
        viewModel = NotchViewModel(
            collapsedSize: collapsedRect.size,
            expandedSize: expandedSize,
            idleHomeSize: idleHomeSize,
            pillSize: pillSize,
            peekSize: peekSize,
            compactPeekSize: compactPeekSize,
            shelfSize: shelfSize,
            calendarSize: calendarSize,
            teleprompterSize: teleprompterSize
        )

        // Invariant 3: the panel is the maximum footprint of any page.
        let maxHeight = max(expandedSize.height, calendarSize.height, teleprompterSize.height)
        let maxWidth = max(expandedSize.width, teleprompterSize.width)
        let maxRect = CGRect(
            x: collapsedRect.midX - maxWidth / 2,
            y: collapsedRect.maxY - maxHeight,
            width: maxWidth,
            height: maxHeight
        )

        panel.contentView = ClickThroughHostingView(
            rootView: NotchRootView(
                viewModel: viewModel,
                nowPlaying: nowPlayingCoordinator,
                liveActivity: liveActivityCoordinator,
                audioTap: audioTap,
                shelfStore: shelfStore,
                systemMonitor: systemMonitorSource,
                calendar: calendarSource,
                    weather: weatherSource
            )
        )
        panel.setFrame(maxRect, display: true)
        panel.orderFrontRegardless()

        applyLiveSettings()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on `.main` already, so no extra task hop.
            MainActor.assumeIsolated { self?.applyLiveSettings() }
        }

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

        // AudioTap's lifetime is tied to actual playback, not the pill/
        // peek UI state above -- it should start the moment something is
        // playing and stop the moment it isn't, independent of whether
        // the notch happens to be expanded to show it.
        audioTapCancellable = nowPlayingCoordinator.$current
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak audioTap] isPlaying in
                if isPlaying {
                    audioTap?.start()
                } else {
                    audioTap?.stop()
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

    /// Invoked from `AtelierApp`'s "Pick a Color..." menu item. The
    /// resulting peek/decay all flows through the existing generic
    /// `identityChanged`/`hasContent` wiring above -- no source-specific
    /// handling needed here, same as Volume/Brightness needing none either.
    func pickColor() {
        guard AtelierSettings.colorPickerEnabled else { return }
        colorPickerSource.pick()
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
