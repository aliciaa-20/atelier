import Foundation

/// Bridges the pure `NotchStateMachine` to SwiftUI. Holds the two sizes the
/// view animates between — `collapsedSize` is real hardware geometry (from
/// `NotchGeometry`, computed once by `NotchController`); `expandedSize` is
/// sized to `ExpandedPlayerView`'s actual content, also computed once by
/// `NotchController` (see `playerContentHeight`).
@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .collapsed

    let collapsedSize: CGSize
    let expandedSize: CGSize
    let pillSize: CGSize
    let peekSize: CGSize

    /// Bumped each time `NotchController` observes the user landing on a
    /// different Space. There's no public API to detect a three-finger swipe
    /// starting (only `NSWorkspace.activeSpaceDidChangeNotification`, which
    /// fires once it's done), so we can't hide the notch during the swipe —
    /// `canJoinAllSpaces` keeps it visible throughout, same as every other
    /// notch app. Incrementing this instead drives a settle animation the
    /// moment you arrive, so the fixed position reads as deliberate.
    @Published private(set) var spaceChangeTick: Int = 0

    init(collapsedSize: CGSize, expandedSize: CGSize, pillSize: CGSize, peekSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.pillSize = pillSize
        self.peekSize = peekSize
    }

    func handle(_ event: NotchEvent) {
        state = NotchStateMachine.reduce(state, on: event)
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
        }
    }
}
