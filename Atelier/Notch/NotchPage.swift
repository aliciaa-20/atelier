/// Which page the expanded notch is showing — orthogonal to `NotchState`
/// on purpose (see the design spec's rejected alternative: folding this
/// into `NotchState` itself would duplicate every hover/peek transition
/// per page). Only matters while `NotchState == .expanded`; `NotchState`
/// itself still governs whether the notch is open at all.
enum NotchPage: Equatable {
    case home
    case shelf
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
