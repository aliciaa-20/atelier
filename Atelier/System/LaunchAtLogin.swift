import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`. The Settings toggle reads
/// `state` live instead of storing a bool: the user can also flip this in
/// System Settings → Login Items, and a stored copy would go stale.
///
/// Caveat: this registers whichever build is running, so a Debug run from
/// Xcode registers the DerivedData copy. Harmless, but odd -- a stable
/// signing identity (ROADMAP Phase 16) is the long-term fix.
enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but macOS wants the user to approve it in Login Items.
        case requiresApproval
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
