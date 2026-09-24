import SwiftUI

/// Per-widget options. Whether a tab exists at all is on the Tabs pane; the
/// options here are greyed out (not hidden) while their tab is off, so the
/// layout doesn't jump. Own sections replace the old menu's indented
/// sub-toggles.
struct WidgetsPane: View {
    @AppStorage(AtelierSettings.calendarEnabledKey) private var calendarEnabled = true
    @AppStorage(AtelierSettings.calendarScrollSwipeKey) private var calendarScrollSwipe = true
    @AppStorage(AtelierSettings.calendarAppBundleIDKey) private var calendarAppBundleID = CalendarAppLauncher.defaultBundleID
    @AppStorage(AtelierSettings.cameraEnabledKey) private var cameraEnabled = true
    @AppStorage(AtelierSettings.cameraHoldOpenKey) private var cameraHoldOpen = false
    @AppStorage(AtelierSettings.colorPickerEnabledKey) private var colorPickerEnabled = true

    var body: some View {
        Form {
            Section("Calendar") {
                Toggle("Scroll-style week swipe", isOn: $calendarScrollSwipe)
                LabeledContent("Opens in") {
                    Button(CalendarAppLauncher.displayName(for: calendarAppBundleID)) {
                        if let id = CalendarAppLauncher.chooseApp() { calendarAppBundleID = id }
                    }
                }
            }
            .disabled(!calendarEnabled)

            Section("Camera") {
                Toggle("Keep notch open while the mirror is on", isOn: $cameraHoldOpen)
            }
            .disabled(!cameraEnabled)

            Section("Color Picker") {
                Toggle("Enable Color Picker", isOn: $colorPickerEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
