import AppKit
import CoreLocation

/// CoreLocation TCC helper -- same thin shape as `CalendarPermission`: a
/// live status read (never cached) plus a deep link to the right pane.
enum LocationPermission {
    static var status: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    /// Asks for When-In-Use access and returns once the user has answered.
    /// A separate manager from `WeatherSource`'s: authorization is per app,
    /// not per manager, so answering here answers it there too.
    @MainActor
    static func requestAccess() async {
        await LocationAuthorizationRequest().run()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Bridges `CLLocationManager`'s delegate callback to `async`. Lives only for
/// the duration of one `run()`.
@MainActor
private final class LocationAuthorizationRequest: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.delegate = self
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Also fires once when the delegate is set, still undetermined.
            guard self.manager.authorizationStatus != .notDetermined else { return }
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
