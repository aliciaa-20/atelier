import SwiftUI

/// Speaks a volume/brightness change for VoiceOver. Atelier suppresses the
/// system HUD, which is what VoiceOver users would otherwise hear. Throttled so
/// holding a key doesn't queue a sentence per repeat.
@MainActor
enum HUDAnnouncer {
    private static var last = Date.distantPast

    static func announce(_ text: String) {
        guard Date().timeIntervalSince(last) > 0.6 else { return }
        last = Date()
        AccessibilityNotification.Announcement(text).post()
    }
}
