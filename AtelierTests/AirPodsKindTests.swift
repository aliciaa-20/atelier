import Testing
@testable import Atelier

struct AirPodsKindTests {
    @Test func recognizesProByAppleProductID() {
        let result = AirPodsKind.classify(vendorID: 0x004C, productID: 0x200E, name: "AirPods Pro")
        #expect(result == .pro)
    }

    @Test func recognizesMaxByAppleProductID() {
        let result = AirPodsKind.classify(vendorID: 0x004C, productID: 0x200A, name: "AirPods Max")
        #expect(result == .max)
    }

    @Test func fallsBackToNameWhenIDsUnavailable() {
        let result = AirPodsKind.classify(vendorID: nil, productID: nil, name: "Alicia's AirPods Pro")
        #expect(result == .pro)
    }

    @Test func nonAppleVendorIsNotAirPods() {
        let result = AirPodsKind.classify(vendorID: 0x1234, productID: 0x200E, name: "Some Headphones")
        #expect(result == nil)
    }

    @Test func unrelatedDeviceNameIsNotAirPods() {
        let result = AirPodsKind.classify(vendorID: nil, productID: nil, name: "Magic Keyboard")
        #expect(result == nil)
    }

    @Test func genericAirPodsNameFallsBackToLegacy() {
        let result = AirPodsKind.classify(vendorID: nil, productID: nil, name: "AirPods")
        #expect(result == .legacy)
    }
}
