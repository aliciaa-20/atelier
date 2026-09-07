/// Pure AirPods model classification -- no IOBluetooth import, so it's
/// unit-testable against fixture vendor/product IDs without a real
/// device connected.
enum AirPodsKind: Equatable {
    case pro, max, basic, legacy

    private static let appleVendorID: UInt16 = 0x004C

    static func classify(vendorID: UInt16?, productID: UInt16?, name: String) -> AirPodsKind? {
        if let vendorID, vendorID == appleVendorID, let productID {
            switch productID {
            case 0x200E, 0x2014, 0x2024: return .pro
            case 0x200A: return .max
            case 0x2013, 0x2019, 0x201B: return .basic
            case 0x2002, 0x200F: return .legacy
            default: break
            }
        }

        let normalized = name.lowercased()
        guard normalized.contains("airpods") else { return nil }
        if normalized.contains("pro") { return .pro }
        if normalized.contains("max") { return .max }
        return .legacy
    }
}
