import SwiftUI

/// Home/Shelf switcher for the expanded notch -- a small dot row, tap a
/// dot to switch, rather than a capsule of labeled tabs.
///
/// Per ADR 0011: surveyed TheBoredTeam/boring.notch's icon-only capsule
/// (`TabSelectionView`/`TabButton`, what the previous version of this file
/// was built from) against jackson-storm/dynamicnotch's
/// `HomePagePageIndicatorView` -- the iOS Home Screen's own page-dot
/// idiom. Chose the dot idiom specifically per direct feedback that the
/// priority is "not too cluttered" -- a dot row is visually lighter than
/// an icon-filled capsule. Tap-only, deliberately: an earlier pass added a
/// swipe gesture (first a plain SwiftUI `DragGesture`, later a full
/// trackpad-swipe mechanism with its own `NSEvent` monitors), and the
/// `NSEvent` version's plumbing was the most likely source of a real
/// regression (the panel not retracting on hover-away) found once shipped.
/// Not worth the risk for a feature this small -- see ADR 0011's
/// consequences section.
///
/// The current page's dot stretches into a short pill rather than just
/// changing color -- the same "current indicator elongates" treatment
/// system page controls use elsewhere in Apple's own UI, so the selection
/// state reads at a glance without needing a highlight capsule behind it.
struct NotchTabBar: View {
    let currentPage: NotchPage
    let onSelect: (NotchPage) -> Void

    private static let dotSize: CGFloat = 6
    private static let selectedDotWidth: CGFloat = 16
    /// The visual dot stays small, but the tappable area around it is
    /// much bigger -- a bare 6pt hit target is uncomfortably small to
    /// aim at (confirmed on-device). 24pt matches Apple's own minimum
    /// comfortable tap-target guidance even though this is a trackpad
    /// pointer, not a finger.
    private static let tapTargetSize: CGFloat = 24

    /// Read live, not cached -- a settings toggle flipped in the menu bar
    /// takes effect on this view's next natural re-render (a hover, a
    /// track change) rather than needing a dedicated observation bridge
    /// for a `UserDefaults` value.
    static var activePages: [NotchPage] {
        var pages: [NotchPage] = [.home]
        if AtelierSettings.shelfEnabled {
            pages.append(.shelf)
        }
        if AtelierSettings.systemMonitorEnabled {
            pages.append(.systemMonitor)
        }
        if AtelierSettings.calendarEnabled {
            pages.append(.calendar)
        }
        return pages
    }

    var body: some View {
        HStack(spacing: -2) {
            ForEach(Self.activePages, id: \.self) { page in
                // A real `Button`, not `.onTapGesture` on a `Capsule` --
                // VoiceOver doesn't expose a tap-gesture-only view as an
                // interactive element at all, so the previous version was
                // entirely unreachable via VoiceOver (couldn't switch tabs).
                Button {
                    onSelect(page)
                } label: {
                    Capsule()
                        .fill(page == currentPage ? Color.white : Color.white.opacity(0.35))
                        .frame(
                            width: page == currentPage ? Self.selectedDotWidth : Self.dotSize,
                            height: Self.dotSize
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
                        .frame(width: Self.tapTargetSize, height: Self.tapTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("\(page.accessibilityName) tab")
                .accessibilityAddTraits(page == currentPage ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        // Split from a symmetric `.padding(.vertical, 2)` -- the top side
        // still needs its 2pt (stacks with `NotchRootView`'s own
        // `+5.5` notch clearance above this view), but the bottom side
        // was pure extra air between the dots and whatever's below
        // (idle clock, player, tab content) -- direct feedback that it
        // still read as too loose after the last round of tightening.
        .padding(.top, 2)
    }
}

private extension NotchPage {
    var accessibilityName: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .systemMonitor: "System Monitor"
        case .calendar: "Calendar"
        }
    }
}
