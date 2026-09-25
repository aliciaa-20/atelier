import AppKit
import CoreAudio
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingCoordinator
    @ObservedObject var liveActivity: LiveActivityCoordinator
    @ObservedObject var audioTap: AudioTap
    @ObservedObject var shelfStore: ShelfStore
    @ObservedObject var systemMonitor: SystemMonitorSource
    @ObservedObject var calendar: CalendarSource
    @ObservedObject var weather: WeatherSource
    @StateObject private var artworkColor = ArtworkColorLoader()
    @StateObject private var camera = CameraMirrorSource()
    @ObservedObject private var teleprompter = TeleprompterModel.shared
    /// Tracked so a hold-open that ends (mirror stopped) knows whether to
    /// retract now or wait for the pointer to actually leave.
    @State private var pointerInside = false
    /// Idle Home shows the weather detail card instead of the clock. Reset
    /// whenever the notch leaves `.expanded`.
    @State private var weatherDetailOpen = false
    @State private var settleScale: CGFloat = 1
    /// A brief dip-and-recover applied to the *whole already-composited*
    /// panel on close -- not a per-branch `.opacity`/`.transition` on
    /// background or content separately. Those were tried (twice) to get a
    /// "fade" feel and both reintroduced real bugs: fading the glass
    /// background while its own shape was resizing rendered a wrong-sized
    /// rectangle, and fading content independently let it render past the
    /// clip during removal. A single opacity value on the outer view,
    /// after background+content are already combined into one image,
    /// can't drift out of sync with itself -- same reasoning as
    /// `settleScale` below, reused for the same reason.
    @State private var closeFadeOpacity: CGFloat = 1
    /// Paired with `closeFadeOpacity` -- a scale dip anchored `.top` (the
    /// same anchor the real notch sits at) so the panel visibly gets
    /// pulled back toward the notch's own position while it fades, not
    /// just shrinking symmetrically in place. Separate from `settleScale`
    /// (Space-change tuck) so the two triggers can't stomp each other's
    /// in-flight animation.
    @State private var closeScale: CGFloat = 1
    @State private var outputDevices: [AudioOutputDevice] = []
    @State private var currentOutputDeviceID: AudioDeviceID?
    /// The last real `liveActivity.topContent` seen, kept around so the
    /// `.peeking` branch has something to render even if the source has
    /// already withdrawn its content (e.g. `BatterySource`'s "Charging"
    /// state, which decays after one poll) while the 2.5s peek animation
    /// is still playing out. Not cleared on retract -- see Fix 3 in the
    /// final review pass.
    @State private var lastPeekContent: LiveActivityContent?

    /// Tracks Accessibility > Display > Reduce Transparency live, not just
    /// at launch -- `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`
    /// fires when the user flips it in System Settings while the app is
    /// running, and `usesGlassBackground` needs to react immediately.
    @StateObject private var accessibilityDisplay = AccessibilityDisplayObserver()

    /// Small/sharp notch-cutout radii at rest, softer/rounder-card radii
    /// once expanded -- matching jackson-storm/dynamicnotch's own
    /// distinction between its collapsed notch shape (~9/13) and its
    /// expanded card shape (34/44, much closer to equal) rather than
    /// reusing one small radius pair at every size.
    ///
    /// `.peeking` uses the stock notch's own sharp 6pt top radius (same as
    /// `.collapsed`/`.pill`) for every peek variant, not just the compact
    /// Volume/Brightness one -- on-device photo evidence (all three peek
    /// kinds photographed against the real physical notch) showed the
    /// softer 14pt top radius previously used for the regular
    /// (track-change/Battery) peek visibly misaligned against the real
    /// notch's own sharper corner immediately above it, the same gap
    /// already fixed for the compact peek. Every peek reads as still
    /// attached to the notch now, not as a separate floating card.
    private var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        switch viewModel.state {
        case .collapsed:
            // Must stay pixel-matched to the real notch (Invariant 7) --
            // kept separate from `.pill` below so a pill-only radius
            // tweak can't accidentally touch this. See ADR 0009.
            return (top: 6, bottom: 14)
        case .pill:
            return (top: 6, bottom: 11)
        case .expanded:
            return (top: 14, bottom: 20)
        case .peeking:
            return (top: 6, bottom: 14)
        case .shelf:
            return (top: 14, bottom: 20)
        }
    }

    /// `viewModel.currentSize` alone can't distinguish a compact peek
    /// (Volume, Brightness -- no title/artist text) from a regular one
    /// (track change, Battery) -- it only knows `state`, not which live
    /// activity content is actually showing. Same `topContent ??
    /// lastPeekContent` fallback as the `.peeking` render branch below, so
    /// the frame size and the content it's sizing around never mismatch
    /// mid-decay. The `.pill` state, unlike peeking, uses one width
    /// (`pillSize`, matching the music pill) for every source -- an
    /// earlier pass gave Volume/Brightness their own narrower notch-width
    /// pill, but on-device that read as too cramped; matching the pill
    /// everything else already uses reads more consistent.
    /// True while the expanded notch is showing the Calendar tab -- the
    /// horizontal swipe changes week there rather than skipping a track.
    private var onCalendarPage: Bool {
        viewModel.state == .expanded && AtelierSettings.calendarEnabled && viewModel.currentPage == .calendar
    }

    private var frameSize: CGSize {
        switch viewModel.state {
        case .peeking:
            let content = liveActivity.topContent ?? lastPeekContent
            return content?.isExpandable == false ? viewModel.compactPeekSize : viewModel.peekSize
        case .expanded:
            // Idle Home (nothing playing, Home tab) gets its own shorter
            // footprint -- far less to show than a real player or the
            // shelf grid, so it shouldn't claim the same vertical space.
            if viewModel.currentPage == .home, nowPlaying.current == nil {
                if weatherDetailOpen, weather.visibleSnapshot != nil {
                    return CGSize(
                        width: viewModel.idleHomeSize.width,
                        height: viewModel.collapsedSize.height + NotchLayout.idleWeatherDetailContentHeight
                    )
                }
                return viewModel.idleHomeSize
            }
            if AtelierSettings.calendarEnabled, viewModel.currentPage == .calendar {
                let count = calendar.events(on: calendar.layoutDay).count
                return CGSize(
                    width: viewModel.calendarSize.width,
                    height: viewModel.collapsedSize.height + NotchLayout.calendarContentHeight(eventCount: count)
                )
            }
            if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter {
                return viewModel.teleprompterSize
            }
            return viewModel.currentSize
        case .pill, .collapsed, .shelf:
            return viewModel.currentSize
        }
    }

    /// `.expanded`/`.peeking`/`.shelf` are the larger, card-scale surfaces
    /// where Liquid Glass reads well. `.collapsed` stays flat black --
    /// Invariant 7 requires it pixel-match the stock notch, which is an
    /// opaque cutout, not a material. `.pill` also stays flat black: it's a
    /// thin sliver hugging the notch, too small/narrow for glass to read as
    /// anything but a compression artifact. Revisit if the pill ever grows
    /// past a sliver.
    ///
    /// Reduce Transparency forces this off entirely regardless of state --
    /// the accessibility setting exists specifically so a translucent,
    /// content-behind-it background never shows. `AtelierSettings
    /// .glassEffectEnabled` is the same kind of override, just user-chosen
    /// instead of system-driven -- checked live like every other setting
    /// in this file (`AtelierSettings.shelfEnabled` etc.), not cached.
    private var usesGlassBackground: Bool {
        guard AtelierSettings.glassEffectEnabled, !accessibilityDisplay.reduceTransparency else { return false }
        switch viewModel.state {
        case .expanded, .peeking, .shelf:
            return true
        case .collapsed, .pill:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if usesGlassBackground {
                    // Regular variant, plain -- no tint. The `liquid-glass`
                    // skill's own design rules are explicit: "tint only
                    // primary actions... when every element is tinted,
                    // nothing stands out." An untinted background lets the
                    // actual glass material read as clear/lensed.
                    //
                    // `.transition(.identity)`, not `.opacity` -- confirmed
                    // on-device via frame-by-frame video: an `.opacity`
                    // crossfade means the glass's own defining shape is
                    // resizing (expanded's large corner radii -> pill's
                    // small ones) at the same instant it's fading, and the
                    // live system material doesn't render cleanly while its
                    // own bounds are actively morphing mid-fade -- it showed
                    // as a solid, wrongly-sized rectangle bleeding through.
                    // Snapping instead of fading avoids ever rendering the
                    // glass mid-resize.
                    // `AtelierSettings.glassIntensity` (Settings slider) as
                    // a plain, continuous `.opacity()` -- not a tint, not a
                    // crossfade. It's a steady render-time property that
                    // updates every frame the slider moves, never tied to a
                    // state transition, so it can't hit the material-mid-
                    // resize or content-escaping-clip bugs a crossfade did.
                    NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom)
                        .fill(.clear)
                        .glassEffect(
                            .regular,
                            in: NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom)
                        )
                        .opacity(AtelierSettings.glassIntensity)
                        .transition(.identity)
                } else {
                    NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom)
                        .fill(Color.black)
                        .transition(.identity)
                }

                if viewModel.state == .expanded {
                    VStack(spacing: 0) {
                        // Both Shelf and System Monitor toggled off in
                        // Settings leaves only Home -- no point showing a
                        // switcher with one destination.
                        if NotchTabBar.activePages.count > 1 {
                            NotchTabBar(currentPage: viewModel.currentPage) { page in
                                withAnimation(NotchAnimations.open) {
                                    viewModel.selectPage(page)
                                }
                            }
                            // Matches PeekPlayerView's own `notchHeight + 4`
                            // clearance -- this used to be `+ 8` stacked on
                            // top of ExpandedPlayerView's/ShelfView's own
                            // separate notch-clearance padding below, which
                            // (now that they're always called with
                            // `notchHeight: 0`, having been superseded by
                            // this tab bar) left the whole header reading as
                            // floating in dead space rather than sitting
                            // flush under the real notch. Bumped `+4` to
                            // `+5.5` -- the dots sat 1.5px into the real
                            // notch's own dead zone at the physical cutout's
                            // edge, confirmed on-device. Eased to `+5` on a
                            // later pass asking for it tighter still -- a
                            // small nudge, not back toward `+4`, since that
                            // exact value is what caused the original
                            // overlap; worth confirming on-device again
                            // before going lower.
                            .padding(.top, viewModel.collapsedSize.height + 5)
                        } else {
                            Color.clear.frame(height: viewModel.collapsedSize.height + 5)
                        }

                        if AtelierSettings.shelfEnabled, viewModel.currentPage == .shelf {
                            ShelfView(store: shelfStore, rootDirectory: shelfStore.rootDirectory, notchHeight: 0)
                                .onAppear { shelfStore.sweepExpired() }
                        } else if AtelierSettings.systemMonitorEnabled, viewModel.currentPage == .systemMonitor {
                            SystemMonitorPageView(source: systemMonitor)
                        } else if AtelierSettings.calendarEnabled, viewModel.currentPage == .calendar {
                            CalendarPageView(source: calendar)
                        } else if AtelierSettings.cameraEnabled, viewModel.currentPage == .camera {
                            CameraMirrorPageView(source: camera) {
                                // Hold-open mode: turning the mirror off
                                // means you're done, so close the notch now
                                // instead of waiting for the pointer to leave.
                                guard AtelierSettings.cameraHoldOpen else { return }
                                withAnimation(NotchAnimations.close) {
                                    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                                }
                            }
                        } else if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter {
                            TeleprompterPageView(model: teleprompter)
                        } else {
                            ExpandedPlayerView(
                                info: nowPlaying.current,
                                weather: weather,
                                weatherDetailOpen: $weatherDetailOpen,
                                waveformColor: artworkColor.color,
                                audioTap: audioTap,
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
                            .onAppear {
                                outputDevices = OutputDeviceManager.availableOutputDevices()
                                currentOutputDeviceID = OutputDeviceManager.currentDefaultOutputDevice()
                            }
                        }
                    }
                    // Root cause of the idle clock bleeding past the
                    // bottom rounded corner: this VStack (tab bar +
                    // content) has no explicit height, so its *natural*
                    // size is shorter than the ZStack's fixed
                    // `frameSize.height` whenever the shown content is
                    // itself compact (e.g. `IdleHomeView`'s two lines) --
                    // and `ZStack`'s default `.center` alignment then
                    // centers the whole block vertically in the leftover
                    // space, pushing it down *in addition to* the tab
                    // bar's own top clearance. `SystemMonitorPageView`/
                    // `ShelfView` happened to mask this by already
                    // declaring their own `maxHeight: .infinity`, but
                    // `ExpandedPlayerView` doesn't -- fixing it here, at
                    // the shared wrapper, rather than in each page
                    // individually, so no future page can reintroduce it.
                    .frame(maxHeight: .infinity, alignment: .top)
                    .overlay(alignment: .top) {
                        if AtelierSettings.teleprompterEnabled, viewModel.currentPage == .teleprompter {
                            TeleprompterControlStrip(
                                model: teleprompter,
                                notchWidth: viewModel.collapsedSize.width,
                                height: viewModel.collapsedSize.height
                            )
                        }
                    }
                    // `.identity`, not `.opacity` -- matching the
                    // background's own transition above. An `.opacity`
                    // fade here while the background snaps instantly made
                    // content visibly linger after the background had
                    // already shrunk to the pill (design feedback: "the
                    // whole thing" should disappear together, not
                    // staggered). Snapping content too also removes any
                    // window where stale, still-rendering content could
                    // render past the now-small clip during that lag.
                    .transition(.identity)
                } else if viewModel.state == .peeking {
                    if let topContent = liveActivity.topContent ?? lastPeekContent {
                        topContent.peekView()
                            .transition(.identity)
                    }
                } else if viewModel.state == .pill {
                    // interruptContent (e.g. Battery briefly surfacing
                    // over music) wins while it's set; otherwise the real
                    // top content shows as usual. A badge (e.g. the
                    // screen-recording dot) composites on top of either --
                    // it never replaces them, see `isBadge`.
                    ZStack {
                        if let content = liveActivity.interruptContent ?? liveActivity.topContent {
                            content.pillView()
                                .transition(.identity)
                        }
                        if let badge = liveActivity.badgeContent {
                            badge.pillView()
                        }
                    }
                } else if viewModel.state == .shelf {
                    ShelfView(store: shelfStore, rootDirectory: shelfStore.rootDirectory, notchHeight: viewModel.collapsedSize.height)
                        .transition(.identity)
                        .onAppear { shelfStore.sweepExpired() }
                } else {
                    // `.collapsed` has no content of its own -- explicit,
                    // not just "no branch matches", so closing into
                    // `.collapsed` (nothing playing) removes old content by
                    // landing on this instead of on nothing at all. Closing
                    // into `.pill` always had a real branch to land on;
                    // `.collapsed` didn't, and going from "something
                    // rendered" to zero matched branches is a different
                    // case for SwiftUI's removal handling than swapping one
                    // rendered view for another -- this keeps that path
                    // identical to every other close.
                    //
                    // KNOWN ISSUE (2026-09-23, unresolved): a left-edge
                    // visual glitch on close specifically when nothing is
                    // playing (landing here, in `.collapsed`, rather than
                    // `.pill`) was reported as still present even after
                    // this fallback branch was added. Two earlier blind
                    // attempts at similar close-transition bugs both turned
                    // out wrong on re-inspection (frame-by-frame video was
                    // what actually found the real cause each time) -- not
                    // guessing a third time without the same kind of
                    // evidence. Needs an on-device video of this specific
                    // path (nothing playing, hover open then close) to
                    // diagnose properly.
                    Color.clear
                        .transition(.identity)
                }
            }
            .frame(width: frameSize.width, height: frameSize.height)
            .clipShape(NotchShape(topCornerRadius: cornerRadii.top, bottomCornerRadius: cornerRadii.bottom))
            // No shadow while `.collapsed` -- Invariant 7 requires that
            // state to be visually indistinguishable from the stock notch,
            // which casts none. Every other state is already a departure
            // from the stock notch's look, and real Dynamic Island shows a
            // subtle shadow once expanded/peeking to read as "lifted" off
            // the wallpaper -- found missing in a ui-review-tahoe pass.
            .shadow(color: .black.opacity(viewModel.state == .collapsed ? 0 : 0.25), radius: 8, y: 2)
            .scaleEffect(settleScale, anchor: .top)
            .scaleEffect(closeScale, anchor: .top)
            .opacity(closeFadeOpacity)
            .contentShape(Rectangle())
            .onHover { hovering in
                pointerInside = hovering
                if AtelierSettings.teleprompterPauseOnHover {
                    teleprompter.setPointerInside(hovering)
                }
                // A non-expandable live activity on top (Volume,
                // Brightness, Battery) has no expanded view of its own --
                // `.hoverStarted` would still force open
                // `ExpandedPlayerView`, showing now-playing info unrelated
                // to what's actually peeking (the same gap Phase 6
                // accepted and deferred, now surfaced for real by Phase
                // 8's peeks). An earlier fix force-closed to the pill on
                // hover instead, but that broke the volume/brightness
                // scrub bar: grabbing it necessarily starts with the mouse
                // entering this same region, so an immediate forced
                // retraction fired before a drag could ever start.
                // Ignoring hover entirely while non-expandable content is
                // up is the actual fix -- its own peek decay timer (reset
                // by every scrub update, see `VolumeSource.publish`)
                // already governs when it closes, with no separate
                // hover-driven transition needed. `nil` topContent
                // (nothing peeking right now) keeps the original
                // hover-to-open behavior for the plain notch/pill.
                guard liveActivity.topContent?.isExpandable ?? true else { return }

                if hovering {
                    withAnimation(NotchAnimations.open) {
                        viewModel.handle(.hoverStarted)
                    }
                } else {
                    // Camera hold-open: only hover-out is suppressed; swipe-close
                    // and tab changes still close/stop (see `CameraHoldOpen`).
                    if CameraHoldOpen.shouldSuppressRetract(
                        holdOpenEnabled: AtelierSettings.cameraHoldOpen,
                        mirrorLive: camera.isLive,
                        currentPage: viewModel.currentPage,
                        state: viewModel.state
                    ) { return }
                    if TeleprompterHoldOpen.shouldSuppressRetract(
                        isPlaying: teleprompter.wantsNotchOpen,
                        currentPage: viewModel.currentPage,
                        state: viewModel.state
                    ) { return }
                    // Slower and more damped than the open — closing snapped
                    // shut at the same speed it opened, which read as
                    // abrupt since there's no destination content to draw
                    // the eye the way the expanding player does on open.
                    withAnimation(NotchAnimations.close) {
                        viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                    }
                }
            }
            .onChange(of: viewModel.state) { _, newState in
                if newState != .expanded { camera.stop(); teleprompter.pause() }
            }
            .onChange(of: viewModel.currentPage) { _, page in
                if page != .camera { camera.stop() }
                // Deliberately NOT paused on app-resign-active: you read
                // while Zoom or a recorder is the frontmost app.
                if page != .teleprompter { teleprompter.pause() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                camera.stop()
            }
            // Hold-open ended (mirror stopped) while the pointer is already
            // outside: do the retract the suppressed hover-out skipped.
            .onChange(of: camera.isLive) { _, live in
                guard !live, !pointerInside, viewModel.state == .expanded else { return }
                withAnimation(NotchAnimations.close) {
                    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
                }
            }
            // Same for the teleprompter: playback ended while the pointer
            // is already outside, so do the retract hold-open skipped.
            .onChange(of: teleprompter.wantsNotchOpen) { _, wants in
                guard !wants, !pointerInside, viewModel.state == .expanded, viewModel.currentPage == .teleprompter else { return }
                withAnimation(NotchAnimations.close) {
                    viewModel.handle(.hoverEnded(isPlaying: liveActivity.hasContent))
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
                        canClose: viewModel.state == .expanded || viewModel.state == .peeking || viewModel.state == .shelf,
                        // Not `liveActivity.topContent?.isExpandable` --
                        // `NowPlayingLiveActivitySource` deliberately
                        // publishes nil while paused (so the pill
                        // disappears), which silently disabled skip too.
                        // `nowPlaying.current` stays populated regardless
                        // of play state, so skipping while paused works.
                        //
                        // On the Calendar page a horizontal swipe changes
                        // week instead (see `onSkipForward` below), so
                        // it's always enabled there.
                        canSkip: onCalendarPage ? !AtelierSettings.calendarScrollSwipeEnabled : nowPlaying.current != nil,
                        canScrub: onCalendarPage && AtelierSettings.calendarScrollSwipeEnabled
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
                        if onCalendarPage {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { calendar.shiftWeek(by: 1) }
                        } else {
                            Task { await nowPlaying.next() }
                        }
                    },
                    onSkipBackward: {
                        if onCalendarPage {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { calendar.shiftWeek(by: -1) }
                        } else {
                            Task { await nowPlaying.previous() }
                        }
                    },
                    onScrub: { calendar.scrub(totalDX: $0) },
                    onScrubEnded: { calendar.endScrub() }
                )
            )
            .modifier(
                NotchDragModifier(
                    onDragEntered: {
                        guard AtelierSettings.shelfEnabled else { return }
                        withAnimation(NotchAnimations.open) {
                            viewModel.handle(.dragEntered)
                        }
                    },
                    onDragExited: {
                        withAnimation(NotchAnimations.close) {
                            viewModel.handle(.dragExited(isPlaying: liveActivity.hasContent))
                        }
                    },
                    onDrop: { providers in
                        for provider in providers {
                            _ = provider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, _ in
                                guard let url else { return }
                                // loadFileRepresentation's url is only valid for the duration of
                                // this handler -- the system may delete the backing file once it
                                // returns, so copy it to a stable staging location synchronously
                                // here, before hopping to the MainActor-isolated ShelfStore.
                                let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                                let staging = stagingDir.appendingPathComponent(url.lastPathComponent)
                                do {
                                    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                                    try FileManager.default.copyItem(at: url, to: staging)
                                } catch {
                                    return
                                }
                                Task { @MainActor in
                                    // `addFile` now MOVES `staging` into the shelf's
                                    // real storage location (avoids a second full-file
                                    // copy on top of the one just made above), which
                                    // empties `staging` but leaves its now-empty parent
                                    // `stagingDir` behind -- clean that up so temp
                                    // directories don't accumulate.
                                    try? shelfStore.addFile(at: staging, originalFilename: url.lastPathComponent)
                                    try? FileManager.default.removeItem(at: stagingDir)
                                }
                            }
                        }
                        withAnimation(NotchAnimations.open) {
                            viewModel.handle(.dropCompleted)
                        }
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
        // Centralized here (rather than at each call site that can trigger
        // a close -- hover, gesture, peek-timer decay, drag-exit) so every
        // close path gets the same fade regardless of which one fired it.
        .onChange(of: viewModel.state) { oldState, newState in
            let wasOpen = oldState == .expanded || oldState == .peeking || oldState == .shelf
            let isNowClosed = newState == .pill || newState == .collapsed
            if newState != .expanded { weatherDetailOpen = false }
            if wasOpen && isNowClosed {
                playCloseFadeAnimation()
            }
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

    /// A quick dip-and-recover on the whole panel's opacity and scale,
    /// layered on top of `cornerRadii`/`frameSize`'s own shrink -- gives
    /// the close a sense of being pulled back into the notch (scale, `.top`
    /// anchored) while fading, instead of just shrinking symmetrically in
    /// place. Doesn't touch background/content transitions individually
    /// (see `closeFadeOpacity`'s own doc for why that's the safe way to do
    /// this).
    private func playCloseFadeAnimation() {
        withAnimation(.easeOut(duration: 0.18)) {
            closeFadeOpacity = 0.55
            closeScale = 0.85
        }
        withAnimation(NotchAnimations.close.delay(0.05)) {
            closeFadeOpacity = 1
            closeScale = 1
        }
    }
}

/// Mirrors `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`
/// as a `@Published` value so SwiftUI re-renders when the user flips
/// Accessibility > Display > Reduce Transparency while the app is running,
/// not just at launch.
@MainActor
final class AccessibilityDisplayObserver: ObservableObject {
    @Published private(set) var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
