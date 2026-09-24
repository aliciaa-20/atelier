import CoreLocation
import Foundation

/// Weather feed for the calendar week strip and the idle Home row. Not a
/// `LiveActivitySource` (no pill), so like `CalendarSource` it just owns
/// state for its views.
///
/// Lightweight by design (CLAUDE.md): no timer, no continuous location.
/// `refreshIfStale()` is called from view `onAppear`s and does nothing while
/// the cached snapshot is under 30 minutes old -- so a closed notch costs
/// nothing. Each refresh is one `requestLocation()` plus one HTTPS request.
/// The last snapshot is persisted so a relaunch shows weather instantly.
///
/// This is the app's first deliberate network call besides artwork -- see
/// `docs/decisions/0015-weather-open-meteo-corelocation.md`.
@MainActor
final class WeatherSource: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var access: Access = .unknown

    private static let cacheKey = "weather.snapshot.v1"

    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private var isRefreshing = false
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        manager.delegate = self
        // A forecast doesn't need better than city-level; coarser is cheaper.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) {
            snapshot = cached
        }
    }

    /// The snapshot only when we're allowed to show it (hidden if the user
    /// denied location -- no nagging, the rest of the UI is unaffected).
    var visibleSnapshot: WeatherSnapshot? {
        access == .denied ? nil : snapshot
    }

    /// Safe to call as often as you like; a no-op while fresh or in flight.
    func refreshIfStale() {
        guard !isRefreshing else { return }
        if let snapshot, !WeatherMath.isStale(fetchedAt: snapshot.fetchedAt) { return }
        isRefreshing = true
        Task {
            await refresh()
            isRefreshing = false
        }
    }

    private func refresh() async {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        guard status == .authorizedAlways else {
            if status != .notDetermined { access = .denied }
            return
        }
        access = .granted

        guard let location = await requestLocation() else { return }
        let unit = TemperatureUnit.forLocale()
        guard let url = WeatherMath.requestURL(latitude: location.coordinate.latitude,
                                               longitude: location.coordinate.longitude,
                                               unit: unit) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let fresh = try WeatherMath.decode(data, fetchedAt: .now, unit: unit)
            snapshot = fresh
            if let encoded = try? JSONEncoder().encode(fresh) {
                defaults.set(encoded, forKey: Self.cacheKey)
            }
        } catch {
            // Offline or a bad payload: keep whatever we had; try again next open.
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined, let c = authContinuation else { return }
            authContinuation = nil
            c.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
