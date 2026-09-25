import AppKit
import AVFoundation
import CoreLocation
import EventKit
import SwiftUI

enum PermissionState {
    case granted
    case notDetermined
    case denied
    /// Can't be read right now (Spotify's Automation, while Spotify is closed).
    case unavailable

    var text: String {
        switch self {
        case .granted: "Granted"
        case .notDetermined: "Not asked yet"
        case .denied: "Denied"
        case .unavailable: "Open Spotify to check"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .notDetermined, .unavailable: .secondary
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
    let microphone: PermissionState
    let speech: PermissionState
    let location: PermissionState
    let spotify: PermissionState

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
            microphone: {
                switch MicrophonePermission.status {
                case .authorized: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            }(),
            speech: {
                switch SpeechPermission.status {
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
            }(),
            spotify: {
                switch AutomationPermission.spotifyStatus() {
                case .granted: .granted
                case .notDetermined: .notDetermined
                case .denied: .denied
                case .targetNotRunning: .unavailable
                }
            }()
        )
    }
}

struct PermissionsPane: View {
    @State private var snapshot = PermissionSnapshot.current()
    @State private var isGrantingAll = false

    /// Only what "Grant All" can actually ask for. Accessibility is excluded:
    /// it can't be requested in-app, so counting it kept the button showing
    /// with nothing left for it to do (its row has its own button).
    private var needsAnything: Bool {
        snapshot.calendar == .notDetermined || snapshot.camera == .notDetermined
            || snapshot.microphone == .notDetermined || snapshot.speech == .notDetermined
            || snapshot.location == .notDetermined || snapshot.spotify == .notDetermined
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
                    deniedNote: "If you just turned this on in System Settings, quit and reopen Atelier.",
                    grant: {
                        _ = await CameraPermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: CameraPermission.openSystemSettings
                )
                PermissionRow(
                    title: "Microphone",
                    detail: "Voice sync in the Teleprompter",
                    state: snapshot.microphone,
                    grant: {
                        _ = await MicrophonePermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: MicrophonePermission.openSystemSettings
                )
                PermissionRow(
                    title: "Speech Recognition",
                    detail: "Voice sync in the Teleprompter (on-device)",
                    state: snapshot.speech,
                    grant: {
                        _ = await SpeechPermission.requestAccess()
                        snapshot = .current()
                    },
                    openSettings: SpeechPermission.openSystemSettings
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
                PermissionRow(
                    title: "Spotify (Automation)",
                    detail: "Now playing and transport controls",
                    state: snapshot.spotify,
                    grant: {
                        await AutomationPermission.requestSpotifyAccess()
                        snapshot = .current()
                    },
                    openSettings: AutomationPermission.openSystemSettings
                )
            } footer: {
                Text("Changes you make in System Settings show up here when you come back to Atelier.")
            }
        }
        .formStyle(.grouped)
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
        if snapshot.microphone == .notDetermined { _ = await MicrophonePermission.requestAccess() }
        if snapshot.speech == .notDetermined { _ = await SpeechPermission.requestAccess() }
        if snapshot.calendar == .notDetermined { _ = await CalendarPermission.requestAccess() }
        if snapshot.location == .notDetermined { await LocationPermission.requestAccess() }
        if snapshot.spotify == .notDetermined { await AutomationPermission.requestSpotifyAccess() }
        snapshot = .current()

        if snapshot.accessibility != .granted { AccessibilityPermission.requestPrompt() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionState
    var deniedNote: String?
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
                if state == .denied, let deniedNote {
                    Text(deniedNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // One VoiceOver element per row: "Camera, The mirror…, Granted".
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var action: some View {
        switch state {
        case .granted, .unavailable:
            EmptyView()
        case .denied:
            Button("Open System Settings", action: openSettings)
        case .notDetermined:
            if let grant {
                Button("Grant Access") { Task { await grant() } }
            } else {
                // Accessibility: no in-app request, only the system prompt.
                Button("Open System Settings", action: openSettings)
            }
        }
    }
}
