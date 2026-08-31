import AppKit
import SwiftUI

/// Owns the notch panel's lifecycle and positions it. Phase 1 only places a
/// static panel over the notch; hover-driven resizing arrives in Phase 2, at
/// which point this becomes responsible for keeping the panel sized to its
/// maximum expanded footprint per invariant 3 in CLAUDE.md.
@MainActor
final class NotchController {
    private let panel = NotchPanel()

    init() {
        panel.contentView = NSHostingView(rootView: NotchRootView())
        positionOverNotch()
        panel.orderFrontRegardless()
    }

    private func positionOverNotch() {
        guard let screen = NSScreen.notchedOrMain else { return }
        let metrics = ScreenMetrics(screen: screen)
        let rect = NotchGeometry.notchRect(for: metrics)
        panel.setFrame(rect, display: true)
    }
}
