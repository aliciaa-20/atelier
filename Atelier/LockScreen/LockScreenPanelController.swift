import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Owns the lock-screen now-playing card's window -- entirely separate
/// from `NotchPanel` (different lifecycle, level, and screen position).
/// See the design spec for why an ordinary window level isn't enough:
/// macOS hides ordinary user-session windows the moment the screen locks,
/// so this delegates into a private CGS space via `SkyLightSpaceOperator`
/// instead.
@MainActor
final class LockScreenPanelController {
    private let nowPlayingCoordinator: NowPlayingCoordinator
    /// Shared with `NotchController`, not a second instance -- see the
    /// call site in `NotchController.init`. A second `AudioTap` would mean
    /// two competing whole-system CoreAudio process taps running at once,
    /// which is wasteful and risks the two aggregate devices fighting over
    /// the same audio hardware. `AudioTap`'s own start/stop is already
    /// driven by `NowPlayingCoordinator.$current.isPlaying` in
    /// `NotchController`, independent of whether the notch panel or this
    /// lock-screen window happens to be visible, so this window can just
    /// observe the same instance passively.
    private let audioTap: AudioTap
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(nowPlayingCoordinator: NowPlayingCoordinator, lockScreenManager: LockScreenManager, audioTap: AudioTap) {
        self.nowPlayingCoordinator = nowPlayingCoordinator
        self.audioTap = audioTap

        Publishers.CombineLatest(lockScreenManager.$isLocked, nowPlayingCoordinator.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked, current in
                self?.updateVisibility(isLocked: isLocked, info: current)
            }
            .store(in: &cancellables)
    }

    /// Matches `NotchAnimations.close`'s ~0.3-0.4s feel, translated to an
    /// AppKit `NSAnimationContext` curve since this is a plain `NSWindow`,
    /// not SwiftUI -- there's no existing AppKit-level animated
    /// show/hide elsewhere in the app to mirror (`NotchPanel` never
    /// animates its own window frame/alpha directly, per invariant 3), so
    /// this is a fresh, self-contained pair of curves.
    private static let visibilityAnimationDuration: TimeInterval = 0.32
    /// How far the card slides (toward the bottom edge it's anchored
    /// near) while fading out on unlock -- small and subtle, not a full
    /// swipe, so it reads as "settling away" rather than being flung
    /// off-screen.
    private static let dismissSlideDistance: CGFloat = 18

    private func updateVisibility(isLocked: Bool, info: NowPlayingInfo?) {
        guard SkyLightSpaceOperator.shared.isAvailable, isLocked, info != nil else {
            hideWindow()
            return
        }
        showWindow()
    }

    private func showWindow() {
        let isAppearing = window == nil || window?.isVisible == false
        let window = window ?? makeWindow()
        self.window = window
        positionWindow(window)

        guard isAppearing else {
            window.orderFrontRegardless()
            return
        }

        // Fade the card in on the way back, matching the graceful fade
        // used on the way out below -- an abrupt appear right after an
        // abrupt disappear would read as inconsistent.
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.visibilityAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            window.animator().alphaValue = 1
        }
    }

    /// Was a bare `window?.orderOut(nil)` -- an instant disappear that
    /// read as an abrupt "pop off" rather than a deliberate transition
    /// (the actual complaint: "when logging in it should go off the
    /// screen more smoothly and gracefully"). Now fades out and slides
    /// down slightly before actually ordering the window out, using
    /// `NSAnimationContext` since `NSWindow.animator()` is how AppKit
    /// (as opposed to SwiftUI's implicit `withAnimation`) animates a
    /// window's own frame/alpha.
    private func hideWindow() {
        guard let window, window.isVisible else {
            window?.orderOut(nil)
            return
        }
        let restingFrame = window.frame
        let dismissedFrame = restingFrame.offsetBy(dx: 0, dy: -Self.dismissSlideDistance)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.visibilityAnimationDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            window.animator().alphaValue = 0
            window.animator().setFrame(dismissedFrame, display: true)
        }, completionHandler: { [weak window] in
            // Only actually order out if nothing re-showed the window
            // mid-animation (e.g. a fast lock/unlock/lock) -- re-checking
            // isLocked here isn't available, but alphaValue tells us
            // whether a subsequent showWindow() already started fading
            // it back in, in which case leave it alone.
            guard let window, window.alphaValue == 0 else { return }
            window.orderOut(nil)
            window.setFrame(restingFrame, display: false)
        })
    }

    private func makeWindow() -> NSWindow {
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: LockScreenMusicCardView.expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        newWindow.isMovable = false

        let hosting = NSHostingView(rootView: LockScreenMusicCardView(
            nowPlaying: nowPlayingCoordinator,
            audioTap: audioTap,
            onPlayPause: { [weak self] in Task { await self?.nowPlayingCoordinator.playPause() } },
            onNext: { [weak self] in Task { await self?.nowPlayingCoordinator.next() } },
            onPrevious: { [weak self] in Task { await self?.nowPlayingCoordinator.previous() } },
            onSeek: { [weak self] time in Task { await self?.nowPlayingCoordinator.seek(to: time) } }
        ))
        newWindow.contentView = hosting

        SkyLightSpaceOperator.shared.delegateWindow(newWindow)
        return newWindow
    }

    /// Bottom-left corner, not bottom-center: the login/password field
    /// always sits centered on the lock screen (that's true across macOS
    /// versions, unlike its exact vertical position), so centering the
    /// card there guarantees an eventual overlap. Both Clayton630/QuartzNotch's
    /// `LockScreenPanelManager.panelFrame` and Ebullioscopic/Atoll's own
    /// lock-screen panel avoid dead-center for the same reason -- QuartzNotch
    /// anchors bottom-left with a fixed inset, which is what this mirrors.
    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.notchedOrMain else { return }
        let size = LockScreenMusicCardView.expandedSize
        let inset: CGFloat = 40
        let origin = CGPoint(
            x: screen.frame.minX + inset,
            y: screen.frame.minY + inset
        )
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
