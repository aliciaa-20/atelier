/// Which page the expanded notch is showing — orthogonal to `NotchState`
/// on purpose (see the design spec's rejected alternative: folding this
/// into `NotchState` itself would duplicate every hover/peek transition
/// per page). Only matters while `NotchState == .expanded`; `NotchState`
/// itself still governs whether the notch is open at all.
enum NotchPage: Hashable, CaseIterable {
    case home
    case shelf
}

extension NotchPage {
    /// Steps to the neighboring page within `pages` (defaults to every
    /// page; callers with a filtered set -- e.g. Shelf disabled in
    /// Settings -- pass that instead). Does not wrap: stepping past
    /// either end returns `nil`, matching `NotchTabBar`'s own tap/drag
    /// (there is no "wrap around" affordance), so a swipe gesture that
    /// means the same motion doesn't behave differently. Shared by
    /// `NotchTabBar`'s drag gesture and the tab-bar-scoped trackpad swipe
    /// in `NotchRootView`, so both interaction paths agree on what "next
    /// page" means.
    func advanced(by offset: Int, in pages: [NotchPage] = NotchPage.allCases) -> NotchPage? {
        guard let index = pages.firstIndex(of: self) else { return nil }
        let newIndex = index + offset
        guard pages.indices.contains(newIndex) else { return nil }
        return pages[newIndex]
    }
}

/// Decides `NotchPage` alongside `NotchStateMachine.reduce` — kept pure
/// and separately testable for the same reason the reducer itself is.
enum NotchPageTransition {
    /// `state` is the *new* `NotchState` after `NotchStateMachine.reduce`
    /// has already run; `currentPage` is the page before this transition.
    static func page(for state: NotchState, currentPage: NotchPage) -> NotchPage {
        switch state {
        case .shelf:
            // A file drag/drop always wins, matching today's behavior.
            return .shelf
        case .collapsed, .pill:
            // Reset so the notch always opens on Home next time, rather
            // than remembering a stale Shelf selection.
            return .home
        case .expanded, .peeking:
            // A manual tab tap (handled outside this function, see
            // NotchViewModel.selectPage) persists across peeks/hovers.
            return currentPage
        }
    }
}
