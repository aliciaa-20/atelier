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

    /// Whether to replay a hover-out that `onHover` swallowed mid-animation.
    ///
    /// `NotchRootView.onHover` ignores an exit while a state/page spring is
    /// running (`contentGeometryUnstable`: the hit-test region is moving under
    /// the cursor), and that early return also skips `pointerInside = false`.
    /// If the cursor really did leave during the spring -- a fast flick across
    /// the notch -- no second exit ever arrives, so the notch stayed open with
    /// `pointerInside` stuck true. Called when the animation settles: true only
    /// for an open state whose flag is still (stale) true while the real mouse
    /// isn't over the panel. Flag already false means the exit was handled, or
    /// the pointer never entered (a track-change peek), so nothing to replay.
    static func shouldRetractAfterSettle(
        state: NotchState,
        pointerOverPanel: Bool,
        pointerInsideFlag: Bool
    ) -> Bool {
        (state == .expanded || state == .peeking) && pointerInsideFlag && !pointerOverPanel
    }

    /// The "Peek on track change" setting gates music-driven peeks; content
    /// whose whole point is the peek (Meeting Join) is exempt.
    static func allowsPeek(peekSettingEnabled: Bool, contentHoversToPeek: Bool) -> Bool {
        peekSettingEnabled || contentHoversToPeek
    }
}
