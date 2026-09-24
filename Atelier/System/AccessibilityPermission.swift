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

    /// Shows the system's own "Atelier would like to control this computer"
    /// prompt (with an Open System Settings button). Accessibility can't be
    /// granted in-app; the user still has to flip the switch. The key is the
    /// literal value of `kAXTrustedCheckOptionPrompt`, which Swift 6 won't
    /// let us reference as a mutable global.
    static func requestPrompt() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
