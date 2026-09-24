import AppKit
import EventKit

/// EventKit TCC helper -- same thin shape as `AccessibilityPermission`: a
/// live status read (never cached) plus a deep link to the right System
/// Settings pane. Read-only access is enough for the Calendar tab, but
/// macOS 14+ only offers "full access" for reading events.
enum CalendarPermission {
    static var status: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static func requestAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
