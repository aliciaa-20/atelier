import SwiftUI

struct WiFiActivityContent: LiveActivityContent {
    let state: WiFiActivityState
    /// Same reasoning as `BatteryActivityContent.notchHeight`: peek
    /// content starts below the physical notch cutout.
    let notchHeight: CGFloat

    var id: String {
        switch state {
        case .connected: "wifi:connected"
        case .disconnected: "wifi:disconnected"
        }
    }

    /// A momentary toast, not ambient status -- worth a brief peek (or a
    /// pill interrupt while music is on top), same shape as a track
    /// change. `WiFiSource` clears it back to `nil` shortly after
    /// publishing, so it never lingers as a permanent pill the way
    /// Battery does.
    var peeksOnChange: Bool { true }

    private var symbolName: String {
        switch state {
        case .connected: "wifi"
        case .disconnected: "wifi.slash"
        }
    }

    private var label: String {
        switch state {
        case .connected: "Wi-Fi Connected"
        case .disconnected: "Wi-Fi Disconnected"
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
