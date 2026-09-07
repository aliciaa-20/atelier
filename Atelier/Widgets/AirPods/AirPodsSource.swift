import Combine
import Foundation
import IOBluetooth

/// Detects AirPods connect/disconnect via `IOBluetoothDevice`'s public
/// connect-notification API -- adapted from Clayton630/QuartzNotch's
/// `BluetoothActivityManager`, read via `gh api` before designing (see
/// check-reference-apps-first). Classification is `AirPodsKind.classify`
/// (Task 9); battery percentage is best-effort via
/// `AirPodsBatteryReader` and omitted from the content when unavailable.
final class AirPodsSource: LiveActivitySource {
    let id = "airpods"
    let priority = NotchLiveActivityPriority.airpods

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    // `deinit` runs nonisolated regardless of this class's actor, and these
    // two properties are only ever touched from `init`/the connect
    // notification callback (both effectively MainActor, since this class
    // is constructed once at app startup and lives for the process
    // lifetime) and from `deinit` at teardown -- `nonisolated(unsafe)`
    // accepts that narrow, understood risk without downgrading concurrency
    // checking for any other IOBluetooth use in this file.
    nonisolated(unsafe) private var connectNotification: IOBluetoothUserNotification?
    nonisolated(unsafe) private var disconnectNotification: IOBluetoothUserNotification?
    private let notchHeight: CGFloat

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    deinit {
        connectNotification?.unregister()
        disconnectNotification?.unregister()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? ""
        let vendorID = (device.value(forKey: "vendorID") as? NSNumber)?.uint16Value
        let productID = (device.value(forKey: "productID") as? NSNumber)?.uint16Value

        guard let kind = AirPodsKind.classify(vendorID: vendorID, productID: productID, name: name) else {
            return
        }

        let percent = AirPodsBatteryReader.percent(for: device)
        subject.send(AirPodsActivityContent(kind: kind, percent: percent, notchHeight: notchHeight))

        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        subject.send(nil)
        disconnectNotification?.unregister()
        disconnectNotification = nil
    }
}
