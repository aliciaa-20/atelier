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

    @AppStorage(AtelierSettings.colorPickerEnabledKey) private var colorPickerEnabled = true
    @AppStorage(AtelierSettings.ghostModeKey) private var ghostMode = false

    init() {
        AtelierSettings.registerDefaults()
        notchController = Self.isRunningTests ? nil : NotchController()
    }

    var body: some Scene {
        // Native `.menu` style: a plain NSMenu (rows, shortcut hints on the
        // right) like every other menu-bar app. The old `.window` style was
        // only needed for the glass-intensity `Slider`, which now lives in
        // the Settings window.
        MenuBarExtra(
            "Atelier",
            systemImage: "rectangle.topthird.inset.filled",
            isInserted: .constant(!Self.isRunningTests)
        ) {
            Text("Atelier 0.1.0")

            Divider()

            // An action, not a setting, so it stays here. Hidden once
            // turned off (Widgets pane), same "no leftover way in"
            // reasoning as before.
            if colorPickerEnabled {
                Button("Pick a Color") {
                    notchController?.pickColor()
                }

                Divider()
            }

            Toggle("Ghost Mode", isOn: $ghostMode)

            Divider()

            // ⌘, works while this menu is open; a global ⌘, would need a
            // real main menu, which an accessory app doesn't have.
            Button("Settings") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")

            Button("Quit Atelier") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
