import AppKit
import SwiftUI

/// Owns the notch panel's lifecycle. Per invariant 3, the panel itself is
/// sized once to the maximum expanded footprint and never resized again —
/// only the SwiftUI content inside it grows/shrinks on hover, which avoids
/// the visible jank of animating an NSWindow's frame directly.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let viewModel: NotchViewModel

    /// Phase 2 placeholder for how much wider/taller the expanded state
    /// grows relative to the real notch — proves the hover mechanism exists.
    /// Phase 4 replaces this with the real player's measured dimensions.
    private static let expandedWidthMargin: CGFloat = 60
    private static let expandedHeight: CGFloat = 60

    init() {
        guard let screen = NSScreen.notchedOrMain else {
            viewModel = NotchViewModel(collapsedSize: .zero, expandedSize: .zero)
            panel.contentView = NSHostingView(rootView: NotchRootView(viewModel: viewModel))
            return
        }

        let metrics = ScreenMetrics(screen: screen)
        let collapsedRect = NotchGeometry.notchRect(for: metrics)
        let expandedSize = CGSize(
            width: collapsedRect.width + Self.expandedWidthMargin,
            height: Self.expandedHeight
        )
        viewModel = NotchViewModel(collapsedSize: collapsedRect.size, expandedSize: expandedSize)

        let maxRect = CGRect(
            x: collapsedRect.midX - expandedSize.width / 2,
            y: collapsedRect.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )

        panel.contentView = NSHostingView(rootView: NotchRootView(viewModel: viewModel))
        panel.setFrame(maxRect, display: true)
        panel.orderFrontRegardless()
    }
}
