import Foundation

/// Pure hover/peek gating decisions, pulled out of `NotchRootView`'s hover
/// handler and `NotchController.triggerPeek` so they're unit-testable --
/// Foundation only, like `NotchState` (Invariant 1).
enum NotchHoverPolicy {
    /// Whether the hover handler should act on a hover change at all.
    ///
    /// Hover into non-expandable content (Volume/Brightness scrub bars, ...)
    /// is ignored so a scrub drag isn't yanked away. Content that opts into
    /// `hoversToPeek` (Meeting Join) is handled in both directions. And
    /// *leaving* a peek always retracts unless a HUD owns it -- otherwise a
    /// hover-peek that outlives its content (Join clicked, grace expired) with
    /// non-expandable Battery underneath would be stuck open.
    static func handlesHover(
        hovering: Bool,
        state: NotchState,
        topContentIsExpandable: Bool?,
        topContentHoversToPeek: Bool,
        hudActive: Bool
    ) -> Bool {
        if state == .expanded || topContentHoversToPeek || (topContentIsExpandable ?? true) { return true }
        return !hovering && state == .peeking && !hudActive
    }

    /// The "Peek on track change" setting gates music-driven peeks; content
    /// whose whole point is the peek (Meeting Join) is exempt.
    static func allowsPeek(peekSettingEnabled: Bool, contentHoversToPeek: Bool) -> Bool {
        peekSettingEnabled || contentHoversToPeek
    }
}
