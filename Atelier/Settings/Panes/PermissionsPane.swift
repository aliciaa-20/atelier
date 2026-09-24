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
    @State private var isGrantingAll = false

    private var needsAnything: Bool {
        snapshot.accessibility != .granted || snapshot.calendar == .notDetermined
            || snapshot.camera == .notDetermined || snapshot.location == .notDetermined
    }

    var body: some View {
        Form {
            if needsAnything {
                Section {
                    LabeledContent("Set up everything Atelier uses") {
                        Button("Grant All") { Task { await grantAll() } }
                            .disabled(isGrantingAll)
                    }
                } footer: {
                    Text("macOS shows one prompt per permission; this asks for each in turn. Accessibility can only be switched on in System Settings.")
                }
            }

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
                    grant: {
                        _ = await CalendarPermission.requestAccess()
                        snapshot = .current()
                    },
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
                    grant: {
                        await LocationPermission.requestAccess()
                        snapshot = .current()
                    },
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

extension PermissionsPane {
    /// One prompt after another, skipping anything already answered.
    /// Accessibility goes last: its prompt points the user at System
    /// Settings, so nothing useful can follow it.
    @MainActor
    fileprivate func grantAll() async {
        isGrantingAll = true
        defer { isGrantingAll = false }

        if snapshot.camera == .notDetermined { _ = await CameraPermission.requestAccess() }
        if snapshot.calendar == .notDetermined { _ = await CalendarPermission.requestAccess() }
        if snapshot.location == .notDetermined { await LocationPermission.requestAccess() }
        snapshot = .current()

        if snapshot.accessibility != .granted { AccessibilityPermission.requestPrompt() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
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
            } else {
                // Accessibility: no in-app request, only the system prompt.
                Button("Open System Settings…", action: openSettings)
            }
        }
    }
}
