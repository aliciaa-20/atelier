import AppKit
import CoreLocation

/// CoreLocation TCC helper -- same thin shape as `CalendarPermission`: a
/// live status read (never cached) plus a deep link to the right pane.
enum LocationPermission {
    static var status: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }
}
