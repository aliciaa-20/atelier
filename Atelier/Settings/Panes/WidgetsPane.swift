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
    @AppStorage(AtelierSettings.meetingJoinEnabledKey) private var meetingJoinEnabled = false
    @State private var meetingAccessDenied = false

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

            Section("Meeting Join") {
                Toggle("Show a Join button before video calls", isOn: $meetingJoinEnabled)
                    .onChange(of: meetingJoinEnabled) { _, on in
                        guard on else { meetingAccessDenied = false; return }
                        guard CalendarPermission.status != .fullAccess else { return }
                        Task {
                            if await !CalendarPermission.requestAccess() {
                                meetingJoinEnabled = false
                                meetingAccessDenied = true
                            }
                        }
                    }
                if meetingAccessDenied {
                    Text("Calendar access is off, so Meeting Join can't see your events.")
                        .foregroundStyle(.secondary)
                    Button("Open System Settings") { CalendarPermission.openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
    }
}
