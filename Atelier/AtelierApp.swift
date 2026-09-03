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

            Toggle("Peek on Track Change", isOn: Binding(
                get: { AtelierSettings.peekOnTrackChangeEnabled },
                set: { UserDefaults.standard.set($0, forKey: AtelierSettings.peekOnTrackChangeKey) }
            ))

            Divider()

            Button("Quit Atelier") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
