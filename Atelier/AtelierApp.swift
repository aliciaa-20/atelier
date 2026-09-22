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
    @AppStorage(AtelierSettings.systemMonitorEnabledKey) private var systemMonitorEnabled = true
    @AppStorage(AtelierSettings.colorPickerEnabledKey) private var colorPickerEnabled = true
    @AppStorage(AtelierSettings.glassEffectEnabledKey) private var glassEffectEnabled = false
    @AppStorage(AtelierSettings.glassIntensityKey) private var glassIntensity = 0.7

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
            VStack(alignment: .leading, spacing: 8) {
                Text("Atelier 0.1.0")

                Divider()

                // `Section` (not another bare `Divider()`) so each group gets a
                // header -- the flat, unlabeled toggle list this replaces read
                // as one undifferentiated block and buried "Pick a Color..."
                // among settings toggles with no visual distinction between
                // "a setting" and "an action to run right now".
                Section("Behavior") {
                    Toggle("Peek on Track Change", isOn: $peekOnTrackChangeEnabled)
                    Toggle("Enable Gestures", isOn: $gesturesEnabled)
                    Toggle("Liquid Glass Effect", isOn: $glassEffectEnabled)

                    // Only surfaced while the effect itself is on -- a slider
                    // for a feature that's off is dead control, not a preview.
                    if glassEffectEnabled {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Glass Transparency")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $glassIntensity, in: 0...1)
                        }
                    }
                }

                Section("Widgets") {
                    Toggle("Enable File Shelf", isOn: $shelfEnabled)
                    Toggle("Enable System Monitor", isOn: $systemMonitorEnabled)
                    Toggle("Enable Color Picker", isOn: $colorPickerEnabled)
                }

                // Hidden, not just disabled, once turned off -- same "no
                // leftover way in" reasoning as `shelfEnabled` gating the
                // Shelf tab's own visibility. No section header here -- a
                // single button doesn't need one; a bare divider is enough to
                // separate it from the toggles above.
                if colorPickerEnabled {
                    Divider()
                    Button("Pick a Color...") {
                        notchController?.pickColor()
                    }
                }

                // Checked live on every menu open, not cached -- matches how
                // the toggles above already read `AtelierSettings` live.
                // `MediaKeyInterceptor` needs this permission for its
                // `CGEventTap`; this is the "visible grant-access path when
                // TCC is denied" the roadmap calls for generally (Phase 16),
                // arriving here out of necessity per the Phase 8 design spec.
                // Kept out of the sections above -- it's neither a setting nor
                // a routine action, it's a one-time permission prompt that
                // should stand out, not blend into either group.
                if !AccessibilityPermission.isGranted {
                    Divider()
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
            .padding(12)
            .frame(width: 240)
        }
        // `.window`, not the default `.menu` style -- `.menu` bridges this
        // content into a native NSMenu, which doesn't support a real
        // interactive `Slider` (the Glass Transparency control above just
        // didn't work as one under it). `.window` renders this as an
        // actual SwiftUI popover instead, where `Slider` works normally.
        .menuBarExtraStyle(.window)
    }
}
