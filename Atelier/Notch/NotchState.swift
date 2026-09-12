/// What the notch is currently showing.
enum NotchState: Equatable {
    /// Visually indistinguishable from the stock notch (Invariant 7).
    case collapsed
    /// A slim always-on sliver while music plays, not hovering.
    case pill
    /// The full player, shown on hover.
    case expanded
    /// The full player, auto-shown briefly on a track change (not hover-
    /// driven). Decays back to the resting state after a timer unless the
    /// user starts actually hovering, at which point `.hoverStarted` takes
    /// over and it behaves exactly like a normal expand.
    case peeking
    /// The file shelf, shown while dragging a file over the notch (or
    /// after a drop, until the mouse leaves). A separate interaction
    /// dimension from hover/peek -- entered by dragging, not hovering.
    case shelf
}

enum NotchEvent {
    case hoverStarted
    /// Carries the current playing state so the resting state after hover
    /// is `.pill` (still playing) or `.collapsed` (not), without the pure
    /// reducer needing to remember anything across calls.
    case hoverEnded(isPlaying: Bool)
    /// Fired by `NowPlayingCoordinator` whenever playback starts/stops.
    case isPlayingChanged(Bool)
    /// Fired on a detected track change, gated by the user's "peek on
    /// track change" setting before it ever reaches the state machine.
    case trackChanged
    /// Fired when playback starts or stops, same gating as `trackChanged`.
    /// A separate case from `isPlayingChanged` (which only governs the
    /// collapsed/pill resting state) so a play/pause toggle earns a peek
    /// too, not just a track change.
    case playbackToggled
    /// Fired by a timer started when entering `.peeking`; a no-op unless
    /// still `.peeking` (i.e. the user hasn't started hovering since).
    case peekTimerElapsed(isPlaying: Bool)
    /// Fired by `NotchDragDetector` when a drag carrying real file content
    /// enters the notch's screen region.
    case dragEntered
    /// Fired by `NotchDragDetector` when a drag exits the region without
    /// dropping. Carries `isPlaying` for the same reason `hoverEnded` does
    /// -- resolving the correct resting state without the reducer
    /// remembering anything across calls.
    case dragExited(isPlaying: Bool)
    /// Fired by `NotchDragDetector` when a drag is released inside the
    /// region. Stays in `.shelf` rather than closing immediately, so the
    /// newly-dropped item is visible.
    case dropCompleted
}

enum NotchStateMachine {
    static func reduce(_ state: NotchState, on event: NotchEvent) -> NotchState {
        switch event {
        case .hoverStarted:
            return state == .shelf ? .shelf : .expanded
        case .hoverEnded(let isPlaying):
            return isPlaying ? .pill : .collapsed
        case .isPlayingChanged(let isPlaying):
            switch state {
            case .expanded, .peeking, .shelf:
                // Don't yank the player/shelf away mid-hover/peek/drag just
                // because playback state changed underneath it.
                return state
            case .collapsed, .pill:
                return isPlaying ? .pill : .collapsed
            }
        case .trackChanged, .playbackToggled:
            // Only takes over from a resting state; an active hover
            // already shows everything a peek would.
            switch state {
            case .collapsed, .pill:
                return .peeking
            case .expanded, .peeking, .shelf:
                return state
            }
        case .peekTimerElapsed(let isPlaying):
            guard state == .peeking else { return state }
            return isPlaying ? .pill : .collapsed
        case .dragEntered:
            switch state {
            case .collapsed, .pill:
                return .shelf
            case .expanded, .peeking, .shelf:
                return state
            }
        case .dragExited(let isPlaying):
            guard state == .shelf else { return state }
            return isPlaying ? .pill : .collapsed
        case .dropCompleted:
            return .shelf
        }
    }
}
