import CoreGraphics

/// The subset of `NSScreen` that notch geometry depends on, expressed without
/// AppKit so this file can be tested without a display. A separate AppKit
/// adapter builds one of these from a real `NSScreen`.
struct ScreenMetrics: Equatable {
    let frame: CGRect
    let safeAreaInsetTop: CGFloat
    let auxiliaryTopLeftWidth: CGFloat
    let auxiliaryTopRightWidth: CGFloat
}

enum NotchGeometry {
    /// Size of the pill shown on a display with no real notch (external
    /// monitors, older MacBooks). Arbitrary but deliberate: wide enough to read
    /// a track title, short enough to look like a HUD rather than a window.
    private static let fallbackSize = CGSize(width: 200, height: 32)

    static func notchRect(for metrics: ScreenMetrics) -> CGRect {
        guard metrics.safeAreaInsetTop > 0 else {
            return fallbackRect(for: metrics)
        }
        let width = metrics.frame.width - metrics.auxiliaryTopLeftWidth - metrics.auxiliaryTopRightWidth
        let height = metrics.safeAreaInsetTop
        let x = metrics.frame.minX + metrics.auxiliaryTopLeftWidth
        let y = metrics.frame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func fallbackRect(for metrics: ScreenMetrics) -> CGRect {
        let x = metrics.frame.midX - fallbackSize.width / 2
        let y = metrics.frame.maxY - fallbackSize.height
        return CGRect(origin: CGPoint(x: x, y: y), size: fallbackSize)
    }
}
