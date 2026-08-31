/// What the notch is currently showing. Grows in later phases (a slim
/// always-on pill, an auto-peek on track change) — kept to exactly the two
/// cases Phase 2 needs for now.
enum NotchState: Equatable {
    case collapsed
    case expanded
}

/// Hover is the only event source for now; more arrive as later phases wire
/// up now-playing data.
enum NotchEvent {
    case hoverStarted
    case hoverEnded
}

enum NotchStateMachine {
    static func reduce(_ state: NotchState, on event: NotchEvent) -> NotchState {
        switch event {
        case .hoverStarted: return .expanded
        case .hoverEnded: return .collapsed
        }
    }
}
