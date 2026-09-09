import SwiftUI

struct BluetoothAlertContent: LiveActivityContent {
    enum Kind: Equatable {
        case connected
        case disconnected
    }

    let kind: Kind
    let deviceName: String
    /// Same reasoning as `WiFiActivityContent.notchHeight`.
    let notchHeight: CGFloat

    var id: String {
        switch kind {
        case .connected: "bluetooth:connected:\(deviceName)"
        case .disconnected: "bluetooth:disconnected:\(deviceName)"
        }
    }

    /// A momentary toast, same reasoning as `WiFiActivityContent`.
    var peeksOnChange: Bool { true }

    private var symbolName: String {
        switch kind {
        case .connected: "cable.connector"
        case .disconnected: "cable.connector.slash"
        }
    }

    private var label: String {
        switch kind {
        case .connected: "\(deviceName) Connected"
        case .disconnected: "\(deviceName) Disconnected"
        }
    }

    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.trailing, 12)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
            .padding(.top, notchHeight + 4)
        )
    }
}
