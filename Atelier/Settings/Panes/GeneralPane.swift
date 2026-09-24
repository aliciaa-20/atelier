import AppKit
import SwiftUI

struct GeneralPane: View {
    @AppStorage(AtelierSettings.peekOnTrackChangeKey) private var peekOnTrackChange = true
    @AppStorage(AtelierSettings.gesturesEnabledKey) private var gesturesEnabled = true

    @State private var launchState = LaunchAtLogin.state
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchBinding)
                if launchState == .requiresApproval {
                    Text("Needs approval in System Settings.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items…") {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Behavior") {
                Toggle("Peek on track change", isOn: $peekOnTrackChange)
                Toggle("Enable gestures", isOn: $gesturesEnabled)
            }
        }
        .formStyle(.grouped)
        // Re-read the real state when returning from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchState = LaunchAtLogin.state
        }
    }

    /// "On" while registered-but-awaiting-approval too: the user has asked
    /// for it, and the note below the toggle says what's still needed.
    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchState == .enabled || launchState == .requiresApproval },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
                launchState = LaunchAtLogin.state
            }
        )
    }
}
