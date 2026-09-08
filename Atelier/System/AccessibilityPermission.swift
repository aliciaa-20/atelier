import AppKit
import ApplicationServices

/// A new TCC type for Atelier (Automation, used for AppleScript/Spotify,
/// is a separate permission) -- `MediaKeyInterceptor`'s `CGEventTap`
/// requires it. Thin on purpose: a live `AXIsProcessTrusted()` check plus a
/// deep-link to the right System Settings pane, matching how
/// `AtelierSettings`'s toggles already read live state rather than caching
/// it.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
