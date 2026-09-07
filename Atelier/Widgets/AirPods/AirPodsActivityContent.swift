import SwiftUI

struct AirPodsActivityContent: LiveActivityContent {
    let kind: AirPodsKind
    let percent: Int?

    var id: String { "airpods:\(kind)" }

    private var name: String {
        switch kind {
        case .pro: "AirPods Pro"
        case .max: "AirPods Max"
        case .basic: "AirPods"
        case .legacy: "AirPods"
        }
    }

    func pillView() -> AnyView {
        AnyView(
            Image(systemName: "airpods")
                .foregroundStyle(.white)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
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
                if let percent {
                    Spacer(minLength: 0)
                    Text("\(percent)%").font(.subheadline).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 9)
        )
    }
}
