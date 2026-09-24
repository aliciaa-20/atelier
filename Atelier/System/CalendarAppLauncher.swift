import AppKit

/// Opens the user's chosen calendar app from the Calendar tab. `calshow:`
/// is iOS-only -- on macOS nothing handles it -- so this launches an app
/// by bundle ID instead. Defaults to Calendar.app; the choice lives in the
/// menu bar (`AtelierSettings.calendarAppBundleID`).
enum CalendarAppLauncher {
    static let defaultBundleID = "com.apple.iCal"

    static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Display name for the menu row; falls back to Calendar if the chosen
    /// app has since been uninstalled.
    static func displayName(for bundleID: String) -> String {
        let url = appURL(for: bundleID) ?? appURL(for: defaultBundleID)
        return url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "Calendar"
    }

    static func open() {
        let url = appURL(for: AtelierSettings.calendarAppBundleID) ?? appURL(for: defaultBundleID)
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Shows an app picker and stores the result. Returns the new bundle ID
    /// (nil if cancelled or the pick has no bundle ID).
    @MainActor
    static func chooseApp() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose the app to open your calendar in"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        return id
    }
}
