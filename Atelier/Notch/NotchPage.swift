/// Which page the expanded notch is showing — orthogonal to `NotchState`
/// on purpose (see the design spec's rejected alternative: folding this
/// into `NotchState` itself would duplicate every hover/peek transition
/// per page). Only matters while `NotchState == .expanded`; `NotchState`
/// itself still governs whether the notch is open at all.
enum NotchPage: String, Hashable, CaseIterable {
    case home
    case shelf
    case systemMonitor
    case calendar
    case camera
}

/// Decides `NotchPage` alongside `NotchStateMachine.reduce` — kept pure
/// and separately testable for the same reason the reducer itself is.
enum NotchPageTransition {
    /// `state` is the *new* `NotchState` after `NotchStateMachine.reduce`
    /// has already run; `currentPage` is the page before this transition.
    /// `firstPage` is the first tab in the user's order (Home unless they
    /// moved it). `previousState` is the state before this transition, so
    /// opening the notch can pick the page *now* -- the order may have
    /// changed while it was collapsed. `enabledPages` lets a tab that was
    /// turned off while selected fall back instead of rendering nothing.
    static func page(
        for state: NotchState,
        currentPage: NotchPage,
        firstPage: NotchPage = .home,
        previousState: NotchState? = nil,
        enabledPages: Set<NotchPage> = Set(NotchPage.allCases)
    ) -> NotchPage {
        switch state {
        case .shelf:
            // A file drag/drop always wins, matching today's behavior.
            return .shelf
        case .collapsed, .pill:
            // Reset so the notch reopens on the first tab rather than
            // remembering a stale Shelf selection.
            return firstPage
        case .expanded, .peeking:
            if previousState == .collapsed || previousState == .pill {
                return firstPage
            }
            // A manual tab tap (handled outside this function, see
            // NotchViewModel.selectPage) persists across peeks/hovers.
            return enabledPages.contains(currentPage) ? currentPage : firstPage
        }
    }
}
