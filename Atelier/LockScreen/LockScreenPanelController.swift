import AppKit
import Combine
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
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(nowPlayingCoordinator: NowPlayingCoordinator, lockScreenManager: LockScreenManager) {
        self.nowPlayingCoordinator = nowPlayingCoordinator

        Publishers.CombineLatest(lockScreenManager.$isLocked, nowPlayingCoordinator.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked, current in
                self?.updateVisibility(isLocked: isLocked, info: current)
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(isLocked: Bool, info: NowPlayingInfo?) {
        guard SkyLightSpaceOperator.shared.isAvailable, isLocked, info != nil else {
            window?.orderOut(nil)
            return
        }
        showWindow()
    }

    private func showWindow() {
        let window = window ?? makeWindow()
        self.window = window
        positionWindow(window)
        window.orderFrontRegardless()
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
            onPlayPause: { [weak self] in Task { await self?.nowPlayingCoordinator.playPause() } },
            onNext: { [weak self] in Task { await self?.nowPlayingCoordinator.next() } },
            onPrevious: { [weak self] in Task { await self?.nowPlayingCoordinator.previous() } },
            onSeek: { [weak self] time in Task { await self?.nowPlayingCoordinator.seek(to: time) } }
        ))
        newWindow.contentView = hosting

        SkyLightSpaceOperator.shared.delegateWindow(newWindow)
        return newWindow
    }

    /// Bottom-center of the screen, clear of the password/Touch ID entry
    /// area (which sits center-screen). 60pt up from the bottom edge --
    /// a starting value, expected to be tuned on-device.
    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.notchedOrMain else { return }
        let size = LockScreenMusicCardView.expandedSize
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 60
        )
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
