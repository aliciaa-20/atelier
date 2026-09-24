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

    /// Launches the chosen app. For Calendar.app it also jumps to `day` via
    /// AppleScript (`view calendar at`) -- needs the one-time Automation
    /// grant for Calendar (`NSAppleEventsUsageDescription` is already set
    /// for Spotify). Any other app, or a denied grant, just gets launched:
    /// there's no portable "open on a date" for third-party calendar apps.
    @MainActor
    static func open(on day: Date) {
        let bundleID = AtelierSettings.calendarAppBundleID
        if bundleID == defaultBundleID, showInCalendarApp(day: day) { return }
        let url = appURL(for: bundleID) ?? appURL(for: defaultBundleID)
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Returns false if the script failed (e.g. Automation denied) so the
    /// caller can fall back to a plain launch.
    @MainActor
    private static func showInCalendarApp(day: Date) -> Bool {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let y = c.year, let m = c.month, let d = c.day else { return false }
        // Set day to 1 first so assigning month can't overflow (e.g. 31 -> Feb).
        let source = """
        set d to current date
        set day of d to 1
        set year of d to \(y)
        set month of d to \(m)
        set day of d to \(d)
        set time of d to 0
        tell application "Calendar"
            activate
            view calendar at d
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
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
