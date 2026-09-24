import Foundation

/// Bridges the pure `NotchStateMachine` to SwiftUI. Holds the two sizes the
/// view animates between — `collapsedSize` is real hardware geometry (from
/// `NotchGeometry`, computed once by `NotchController`); `expandedSize` is
/// sized to `ExpandedPlayerView`'s actual content, also computed once by
/// `NotchController` (see `playerContentHeight`).
@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .collapsed
    @Published private(set) var currentPage: NotchPage = AtelierSettings.firstPage

    let collapsedSize: CGSize
    let expandedSize: CGSize
    /// A shorter `.expanded` footprint for the Home tab's idle content
    /// (date/time + battery %) -- much less to show than a real player, so
    /// it shouldn't claim the same vertical space. `NotchRootView` picks
    /// between this and `expandedSize` based on whether anything's playing,
    /// not `NotchViewModel` itself, which stays state-only.
    let idleHomeSize: CGSize
    let pillSize: CGSize
    let peekSize: CGSize
    /// A smaller `.peeking` footprint for content with no title/artist
    /// text (Volume, Brightness) -- `NotchRootView` picks between this and
    /// `peekSize` based on what's actually peeking, not `NotchViewModel`
    /// itself, which stays state-only and unaware of live activity content.
    let compactPeekSize: CGSize
    /// The file shelf's own footprint -- wide enough for a short horizontal
    /// row of items, shorter than the full player since there's no
    /// scrubber/transport row to fit.
    let shelfSize: CGSize
    /// The Calendar tab's own, taller footprint -- a week strip plus a few
    /// agenda rows doesn't fit the player's 134pt content height. Only
    /// `NotchRootView.frameSize` picks it (state alone can't say which page
    /// is showing); the panel itself is already sized to the tallest of these.
    let calendarSize: CGSize

    /// Bumped each time `NotchController` observes the user landing on a
    /// different Space. There's no public API to detect a three-finger swipe
    /// starting (only `NSWorkspace.activeSpaceDidChangeNotification`, which
    /// fires once it's done), so we can't hide the notch during the swipe —
    /// `canJoinAllSpaces` keeps it visible throughout, same as every other
    /// notch app. Incrementing this instead drives a settle animation the
    /// moment you arrive, so the fixed position reads as deliberate.
    @Published private(set) var spaceChangeTick: Int = 0

    init(collapsedSize: CGSize, expandedSize: CGSize, idleHomeSize: CGSize, pillSize: CGSize, peekSize: CGSize, compactPeekSize: CGSize, shelfSize: CGSize, calendarSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.idleHomeSize = idleHomeSize
        self.pillSize = pillSize
        self.peekSize = peekSize
        self.compactPeekSize = compactPeekSize
        self.shelfSize = shelfSize
        self.calendarSize = calendarSize
    }

    func handle(_ event: NotchEvent) {
        let newState = NotchStateMachine.reduce(state, on: event)
        currentPage = NotchPageTransition.page(for: newState, currentPage: currentPage, firstPage: AtelierSettings.firstPage)
        state = newState
    }

    /// Called directly from a tab tap — bypasses `NotchPageTransition` since
    /// this is a UI action, not a state-machine transition.
    func selectPage(_ page: NotchPage) {
        currentPage = page
    }

    func notchLandedOnNewSpace() {
        spaceChangeTick += 1
    }

    var currentSize: CGSize {
        switch state {
        case .collapsed: collapsedSize
        case .pill: pillSize
        case .expanded: expandedSize
        case .peeking: peekSize
        case .shelf: shelfSize
        }
    }
}
