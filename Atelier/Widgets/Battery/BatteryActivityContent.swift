import SwiftUI

struct BatteryActivityContent: LiveActivityContent {
    let state: BatteryActivityState

    var id: String {
        switch state {
        case .charging: "battery:charging"
        case .low(let percent): "battery:low:\(percent)"
        case .full: "battery:full"
        }
    }

    private var symbolName: String {
        switch state {
        case .charging: "bolt.fill"
        case .low: "battery.25"
        case .full: "battery.100"
        }
    }

    private var tint: Color {
        switch state {
        case .charging: .green
        case .low: .red
        case .full: .green
        }
    }

    private var label: String {
        switch state {
        case .charging: "Charging"
        case .low(let percent): "Battery Low  \(percent)%"
        case .full: "Full Battery"
        }
    }

    func pillView() -> AnyView {
        AnyView(
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
        )
    }
}
