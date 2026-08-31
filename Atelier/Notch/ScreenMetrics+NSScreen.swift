import AppKit

extension ScreenMetrics {
    /// Reads the metrics `NotchGeometry` needs directly off a real screen.
    /// Kept as a one-line-per-field passthrough on purpose — the logic worth
    /// testing already happened in `NotchGeometry`, not here.
    init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaInsetTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width ?? 0
        )
    }
}

extension NSScreen {
    /// The display with a physical notch, or the main screen as a fallback for
    /// notchless setups (external monitors, older MacBooks).
    static var notchedOrMain: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
