import SwiftUI

/// Home/Shelf switcher for the expanded notch -- a small dot row (tap a
/// dot, or drag anywhere across the row) rather than a capsule of labeled
/// tabs.
///
/// Per ADR 0011: surveyed TheBoredTeam/boring.notch's icon-only capsule
/// (`TabSelectionView`/`TabButton`, what the previous version of this file
/// was built from) against jackson-storm/dynamicnotch's
/// `HomePagePageIndicatorView` -- the iOS Home Screen's own page-dot
/// idiom, swipeable, used there to switch between notch "pages". Chose the
/// dot idiom specifically per direct feedback that the priority is "not
/// too cluttered" -- a dot row is visually lighter than an icon-filled
/// capsule. Unlike dynamicnotch's own dots (drag-only), each dot here is
/// also directly tappable: `NotchPage` is two cases today, and losing a
/// one-tap route to the one non-Home destination isn't worth the extra
/// minimalism for so few pages.
///
/// The current page's dot stretches into a short pill rather than just
/// changing color -- the same "current indicator elongates" treatment
/// system page controls use elsewhere in Apple's own UI, so the selection
/// state reads at a glance without needing a highlight capsule behind it.
struct NotchTabBar: View {
    let currentPage: NotchPage
    let onSelect: (NotchPage) -> Void

    private static let pages = NotchPage.allCases
    private static let dotSize: CGFloat = 6
    private static let selectedDotWidth: CGFloat = 16
    private static let dragThreshold: CGFloat = 30

    @State private var hasAdvancedThisDrag = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.pages, id: \.self) { page in
                Capsule()
                    .fill(page == currentPage ? Color.white : Color.white.opacity(0.35))
                    .frame(
                        width: page == currentPage ? Self.selectedDotWidth : Self.dotSize,
                        height: Self.dotSize
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
                    .onTapGesture { onSelect(page) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    /// Fires once per continuous drag past the threshold, matching
    /// dynamicnotch's own single-step-per-gesture page switching rather
    /// than tracking absolute finger position -- simpler, and correct for
    /// only two pages.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !hasAdvancedThisDrag else { return }
                if value.translation.width < -Self.dragThreshold {
                    advance(by: 1)
                } else if value.translation.width > Self.dragThreshold {
                    advance(by: -1)
                }
            }
            .onEnded { _ in hasAdvancedThisDrag = false }
    }

    private func advance(by delta: Int) {
        guard let index = Self.pages.firstIndex(of: currentPage) else { return }
        let newIndex = index + delta
        guard Self.pages.indices.contains(newIndex) else { return }
        hasAdvancedThisDrag = true
        onSelect(Self.pages[newIndex])
    }
}
