import SwiftUI

/// A two-item Home/Shelf segmented control shown above the expanded
/// notch's content. Adapted from TheBoredTeam/boring.notch's
/// `TabSelectionView`/`TabButton` (read via `gh api` per
/// check-reference-apps-first) — same capsule-with-sliding-highlight
/// shape, simplified to this app's two fixed tabs instead of a
/// data-driven list.
struct NotchTabBar: View {
    let currentPage: NotchPage
    let onSelect: (NotchPage) -> Void

    private static let tabs: [(page: NotchPage, label: String)] = [
        (.home, "Home"),
        (.shelf, "Shelf")
    ]

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs, id: \.page) { tab in
                Button {
                    onSelect(tab.page)
                } label: {
                    Text(tab.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(currentPage == tab.page ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if currentPage == tab.page {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .matchedGeometryEffect(id: "tabHighlight", in: highlight)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .clipShape(Capsule())
    }
}
