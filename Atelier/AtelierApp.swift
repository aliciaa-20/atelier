import SwiftUI

/// Atelier is a menu-bar-only app: `LSUIElement` is true in Info.plist, so it has
/// no Dock icon and no main window. The only always-present UI is the menu bar
/// item defined below, which exists so there is a way to quit.
///
/// The notch panel itself is not a SwiftUI `Scene` — it is a borderless `NSPanel`
/// managed by `NotchController` (Phase 1), because SwiftUI has no way to express
/// a window pinned above the menu bar.
@main
struct AtelierApp: App {
    /// Hosted unit tests launch this app as their test host. Skip the menu bar
    /// item in that case so test runs don't litter the user's menu bar.
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Held for the app's lifetime; `NotchController` owns the panel itself.
    private let notchController: NotchController?

    /// `@AppStorage`, not a manual `Binding(get:set:)` reading
    /// `AtelierSettings`/`UserDefaults` directly -- a plain `Binding`
    /// closure pair has no way to tell SwiftUI the underlying value
    /// changed, since raw `UserDefaults` isn't observed. The setting
    /// really did change (other readers picked it up fine on their next
    /// live read), but the `Toggle`'s own checkmark never visually
    /// flipped, since nothing told this view to re-render. `@AppStorage`
    /// wraps the same keys with real KVO-backed observation, so the
    /// checkmark updates immediately. Confirmed on-device as a real bug
    /// before this fix.
    @AppStorage(AtelierSettings.peekOnTrackChangeKey) private var peekOnTrackChangeEnabled = true
    @AppStorage(AtelierSettings.gesturesEnabledKey) private var gesturesEnabled = true
    @AppStorage(AtelierSettings.shelfEnabledKey) private var shelfEnabled = true

    init() {
        AtelierSettings.registerDefaults()
        notchController = Self.isRunningTests ? nil : NotchController()
    }

    var body: some Scene {
        MenuBarExtra(
            "Atelier",
            systemImage: "rectangle.topthird.inset.filled",
            isInserted: .constant(!Self.isRunningTests)
        ) {
            Text("Atelier 0.1.0")

            Divider()

            Toggle("Peek on Track Change", isOn: $peekOnTrackChangeEnabled)
            Toggle("Enable Gestures", isOn: $gesturesEnabled)
            Toggle("Enable File Shelf", isOn: $shelfEnabled)

            // Checked live on every menu open, not cached -- matches how
            // the toggles above already read `AtelierSettings` live.
            // `MediaKeyInterceptor` needs this permission for its
            // `CGEventTap`; this is the "visible grant-access path when
            // TCC is denied" the roadmap calls for generally (Phase 16),
            // arriving here out of necessity per the Phase 8 design spec.
            if !AccessibilityPermission.isGranted {
                Button("Grant Accessibility Access...") {
                    AccessibilityPermission.openSystemSettings()
                }
            }

            Divider()

            Button("Quit Atelier") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
