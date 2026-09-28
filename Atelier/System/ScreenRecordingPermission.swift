import AppKit
import CoreGraphics

/// Screen Recording TCC helper -- same thin shape as `AccessibilityPermission`:
/// a live, uncached status read plus a deep link to the right pane. Binary
/// like Accessibility (macOS doesn't distinguish "not asked yet" from
/// "denied" for `CGPreflightScreenCaptureAccess`), so it can't be requested
/// with a completion handler the way Camera/Microphone can -- the real
/// prompt appears the first time `BendEffectController` actually starts an
/// `SCStream`.
enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPrompt() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
