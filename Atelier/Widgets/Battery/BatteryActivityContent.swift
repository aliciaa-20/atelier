import SwiftUI

struct BatteryActivityContent: LiveActivityContent {
    let state: BatteryActivityState
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so peek content starts below it.
    let notchHeight: CGFloat

    /// Deliberately does NOT include `.low`'s percent -- see Fix 6 in the
    /// final review pass. Including the percent made `LiveActivityCoordinator`
    /// treat every 1% drop as a new peek-worthy identity change; the percent
    /// still updates live in `label`, just not in identity.
    var id: String {
        switch state {
        case .charging: "battery:charging"
        case .low: "battery:low"
        case .full: "battery:full"
        }
    }

    private var symbolName: String {
        switch state {
        case .charging: "bolt.fill"
        case .low(let percent):
            if percent <= 10 { "battery.0" }
            else if percent <= 35 { "battery.25" }
            else { "battery.50" }
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
            HStack(spacing: 0) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                    .font(.system(size: 12))

                Spacer(minLength: 0)
            }
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
            .padding(.top, notchHeight + 4)
        )
    }
}
