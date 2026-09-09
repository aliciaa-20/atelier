import Combine
import Foundation
import IOBluetooth

/// Watches system-wide Bluetooth connect/disconnect notifications,
/// publishing a momentary toast per device that self-clears a few seconds
/// later -- the rich `AirPodsActivityContent` (name + battery) for a
/// device `AirPodsKind.classify` recognizes, the generic
/// `BluetoothAlertContent` (name only) for anything else.
///
/// This supersedes the old `AirPodsSource`, which is no longer
/// registered: that one used `IOBluetoothDevice.register(forConnectNotifications:)`,
/// which crashes this process 100% of the time on-device (see git history
/// for the removed registration comment in `NotchController`). This
/// source reaches the same `AirPodsKind`/`AirPodsActivityContent` pieces
/// `AirPodsSource` built, but detects
/// connect/disconnect the way jackson-storm/dynamicnotch's
/// `BluetoothService+Lifecycle` does (read via `gh api` before designing,
/// see check-reference-apps-first): observe `DistributedNotificationCenter`'s
/// `IOBluetoothDevice{Connected,Disconnected}Notification` (system-wide,
/// IPC-only -- no `IOBluetoothRegisterForNotifications` call, so no
/// crash), then re-poll `IOBluetoothDevice.pairedDevices()` to find out
/// *which* device changed, since a distributed notification's payload
/// isn't a live `IOBluetoothDevice` reference across the process
/// boundary.
///
/// The DNC notification alone proved unreliable on-device (confirmed: no
/// notification fired across a real connect/disconnect during testing) --
/// dynamicnotch's own `BluetoothService` doesn't rely on it exclusively
/// either, running a 3s polling timer (`startPollingForChanges`) as a
/// backstop. This keeps both: the notification for a fast response when it
/// does fire, the timer as the actual source of truth.
///
/// AirPods disconnect is deliberately silent (no toast) -- matches
/// `AirPodsSource.deviceDisconnected`'s own behavior, which just cleared
/// its content rather than announcing the disconnect.
final class BluetoothSource: LiveActivitySource {
    let id = "bluetoothAlert"
    // Shares AirPods' priority now that this source is what actually
    // surfaces AirPods content -- see the type's own doc comment.
    let priority = NotchLiveActivityPriority.airpods

    private static let toastDuration: Duration = .seconds(4)
    /// Same reasoning as dynamicnotch's own 0.5s delay: the paired-device
    /// list's `isConnected()` state can lag slightly behind the
    /// notification firing.
    private static let settleDelay: Duration = .milliseconds(500)
    /// Shorter than dynamicnotch's own 3s `pollingInterval` -- confirmed
    /// on-device that 3s reads noticeably slower than macOS's own native
    /// connect banner. `pairedDevices()`/`isConnected()` are a local
    /// IOKit query, not a radio scan, so polling faster doesn't cost a
    /// meaningful amount more.
    private static let pollingInterval: TimeInterval = 1.0

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private var connectedAddresses: Set<String> = []
    private var clearTask: Task<Void, Never>?
    // `deinit` runs nonisolated regardless of this class's actor -- same
    // reasoning as `BatterySource.runLoopSource`.
    nonisolated(unsafe) private var pollingTimer: Timer?

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        connectedAddresses = Self.currentlyConnectedAddresses()

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self,
            selector: #selector(handleChangeNotification),
            name: NSNotification.Name("IOBluetoothDeviceConnectedNotification"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(handleChangeNotification),
            name: NSNotification.Name("IOBluetoothDeviceDisconnectedNotification"),
            object: nil
        )

        pollingTimer = Timer.scheduledTimer(withTimeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
    }

    deinit {
        clearTask?.cancel()
        pollingTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private static func currentlyConnectedAddresses() -> Set<String> {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return Set(devices.filter { $0.isConnected() }.compactMap(\.addressString))
    }

    @objc private func handleChangeNotification() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            self?.reconcile()
        }
    }

    private func reconcile() {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        let currentlyConnected = devices.filter { $0.isConnected() }
        let currentAddresses = Set(currentlyConnected.compactMap(\.addressString))

        let newlyConnected = currentlyConnected.filter { device in
            guard let address = device.addressString else { return false }
            return !connectedAddresses.contains(address)
        }
        let newlyDisconnected = devices.filter { device in
            guard let address = device.addressString else { return false }
            return connectedAddresses.contains(address) && !currentAddresses.contains(address)
        }

        connectedAddresses = currentAddresses

        if let device = newlyConnected.first {
            publishConnected(device)
        } else if let device = newlyDisconnected.first {
            publishDisconnected(device)
        }
    }

    private static func classify(_ device: IOBluetoothDevice) -> AirPodsKind? {
        let vendorID = (device.value(forKey: "vendorID") as? NSNumber)?.uint16Value
        let productID = (device.value(forKey: "productID") as? NSNumber)?.uint16Value
        return AirPodsKind.classify(vendorID: vendorID, productID: productID, name: device.name ?? "")
    }

    private func publishConnected(_ device: IOBluetoothDevice) {
        if let kind = Self.classify(device) {
            publish(AirPodsActivityContent(kind: kind, notchHeight: notchHeight))
        } else {
            publish(BluetoothAlertContent(kind: .connected, deviceName: device.name ?? "Device", notchHeight: notchHeight))
        }
    }

    private func publishDisconnected(_ device: IOBluetoothDevice) {
        guard Self.classify(device) == nil else { return }
        publish(BluetoothAlertContent(kind: .disconnected, deviceName: device.name ?? "Device", notchHeight: notchHeight))
    }

    private func publish(_ content: LiveActivityContent) {
        clearTask?.cancel()
        subject.send(content)
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            guard !Task.isCancelled else { return }
            self?.subject.send(nil)
        }
    }
}
