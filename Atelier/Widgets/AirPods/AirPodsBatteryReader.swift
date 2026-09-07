import IOBluetooth

/// AirPods battery percentage via an undocumented `IOBluetoothDevice`
/// key -- no stability guarantee across macOS versions. Isolated to this
/// one file (per the design spec's decision) so a future OS update
/// breaking it only touches here; `AirPodsSource` treats a `nil` result
/// as "no percentage available," not an error.
enum AirPodsBatteryReader {
    static func percent(for device: IOBluetoothDevice) -> Int? {
        guard let value = device.value(forKey: "batteryPercentCombined") as? NSNumber else {
            return nil
        }
        return value.intValue
    }
}
