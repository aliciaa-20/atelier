import SwiftUI

struct AirPodsActivityContent: LiveActivityContent {
    let kind: AirPodsKind
    /// Same reasoning as `PeekPlayerView.notchHeight`: the physical notch
    /// cutout has no display pixels, so peek content starts below it.
    let notchHeight: CGFloat

    var id: String { "airpods:\(kind)" }

    private var name: String {
        switch kind {
        case .pro: "AirPods Pro"
        case .max: "AirPods Max"
        case .basic: "AirPods"
        case .legacy: "AirPods"
        }
    }

    /// Trailing-aligned icon, same convention as `WiFiActivityContent`/
    /// `BluetoothAlertContent` -- a leading `Spacer` plus trailing padding
    /// keeps it clear of the notch's dead zone, matching the ~18pt-per-
    /// flank budget documented on `PillPlayerView.artworkSide`.
    func pillView() -> AnyView {
        AnyView(
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: "airpods")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.trailing, 12)
        )
    }

    func peekView() -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: "airpods")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected").font(.caption).foregroundStyle(.white.opacity(0.65))
                    Text(name).font(.subheadline).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
            .padding(.top, notchHeight + 4)
        )
    }
}
