import Combine
import Foundation
import Network

/// Watches `NWPathMonitor` for Wi-Fi connectivity changes, publishing a
/// momentary `WiFiActivityContent` toast that self-clears a few seconds
/// later. Connectivity only, not the network name -- see
/// `WiFiActivityState`'s doc comment for why.
///
/// Started from a CoreWLAN `CWEventDelegate` design (adapted from
/// jackson-storm/dynamicnotch's `WifiMonitor`, see
/// check-reference-apps-first), but `CWInterface.ssid()` turned out to
/// need Location Services authorization Atelier doesn't request, and its
/// `@objc` delegate callbacks are invoked directly on CoreWLAN's own
/// background queue -- which crashed on-device under this project's
/// `-default-isolation=MainActor` build setting (an implicit MainActor
/// executor check on an ObjC entry point invoked off-main). `NWPathMonitor`
/// avoids both: no CoreWLAN, and its `pathUpdateHandler` is a plain
/// closure, not an isolated method, so the same crash can't happen.
final class WiFiSource: LiveActivitySource {
    let id = "wifi"
    let priority = NotchLiveActivityPriority.wifi

    private static let toastDuration: Duration = .seconds(4)

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let monitorQueue = DispatchQueue(label: "com.aliciapereira.Atelier.WiFiSource")
    private var previouslyConnected: Bool?
    private var clearTask: Task<Void, Never>?

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight

        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.handleChange(isConnected: isConnected)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        clearTask?.cancel()
        monitor.cancel()
    }

    private func handleChange(isConnected: Bool) {
        guard let state = WiFiActivityState.evaluate(isConnected: isConnected, previouslyConnected: previouslyConnected) else {
            previouslyConnected = isConnected
            return
        }
        previouslyConnected = isConnected

        clearTask?.cancel()
        subject.send(WiFiActivityContent(state: state, notchHeight: notchHeight))
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            guard !Task.isCancelled else { return }
            self?.subject.send(nil)
        }
    }
}
