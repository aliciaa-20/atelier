import Foundation

/// Bridges the pure `NotchStateMachine` to SwiftUI. Holds the two sizes the
/// view animates between — `collapsedSize` is real hardware geometry (from
/// `NotchGeometry`, computed once by `NotchController`), `expandedSize` is a
/// Phase 2 placeholder to prove the hover mechanism; Phase 4 replaces it with
/// the real player's dimensions.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .collapsed

    let collapsedSize: CGSize
    let expandedSize: CGSize

    init(collapsedSize: CGSize, expandedSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
    }

    func handle(_ event: NotchEvent) {
        state = NotchStateMachine.reduce(state, on: event)
    }

    var currentSize: CGSize {
        switch state {
        case .collapsed: collapsedSize
        case .expanded: expandedSize
        }
    }
}
