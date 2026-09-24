import AppKit
import AVFoundation
import CoreLocation
import EventKit
import SwiftUI

enum PermissionState {
    case granted
    case notDetermined
    case denied

    var text: String {
        switch self {
        case .granted: "Granted"
        case .notDetermined: "Not asked yet"
        case .denied: "Denied"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .notDetermined: .secondary
        case .denied: .red
        }
    }
}

/// Read fresh from the OS every time (never cached) -- the user can change
/// any of these in System Settings while Atelier is running.
private struct PermissionSnapshot {
    let accessibility: PermissionState
    let calendar: PermissionState
    let camera: PermissionState
    let location: PermissionState

    static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AccessibilityPermission.isGranted ? .granted : .denied,
            calendar: {
                switch CalendarPermission.status {
                case .fullAccess: .granted
                case .notDetermined: .notDetermined
                default: .denied  // denied, restricted, or write-only (we read events)
                }
            }(),
            camera: {
                switch CameraPermission.status {
                case .authorized: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }(),
            location: {
                switch LocationPermission.status {
                case .authorizedAlways: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }()
        )
    }
}

struct PermissionsPane: View {
    @State private var snapshot = PermissionSnapshot.current()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Volume and brightness keys",
                    state: snapshot.accessibility,
                    openSettings: AccessibilityPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Calendar",
                    detail: "Events in the Calendar tab",
                    state: snapshot.calendar,
                    notAskedHint: "Open the Calendar tab to be asked.",
                    openSettings: CalendarPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Camera",
                    detail: "The mirror in the Camera tab",
                    state: snapshot.camera,
                    grant: {
                        _ = await CameraPermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: CameraPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Location",
                    detail: "Local weather",
                    state: snapshot.location,
                    notAskedHint: "Open the Weather view on Home to be asked.",
                    openSettings: LocationPermission.openSystemSettings
                )
            } footer: {
                Text("Changes you make in System Settings show up here when you come back to Atelier.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            snapshot = .current()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    /// Shown in place of a button when there's no in-app way to trigger the
    /// system prompt from here (only Camera has a ready request helper).
    var notAskedHint: String?
    var grant: (() async -> Void)?
    let openSettings: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(state.text)
                    .foregroundStyle(state.color)
                action
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // One VoiceOver element per row: "Camera, The mirror…, Granted".
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .granted:
            EmptyView()
        case .denied:
            Button("Open System Settings…", action: openSettings)
        case .notDetermined:
            if let grant {
                Button("Grant Access") { Task { await grant() } }
            } else if let notAskedHint {
                Text(notAskedHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
