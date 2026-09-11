import Combine
import Foundation

/// Priorities for every `LiveActivitySource`, kept in one place so a new
/// source's ranking is a one-line addition, not a magic number buried in
/// its own file.
enum NotchLiveActivityPriority {
    /// Volume and Brightness share these two values rather than one fixed
    /// slot each -- whichever was touched most recently reports
    /// `.systemHUDActive`, the other `.systemHUDInactive`, via
    /// `SystemHUDOrder`. Real macOS replaces whichever OSD is showing the
    /// instant the *other* key is pressed, not after the first one
    /// decays; a fixed volume-always-above-brightness ranking couldn't
    /// express that. See `SystemHUDOrder`'s own doc comment.
    static let systemHUDActive = 20
    static let systemHUDInactive = 19
    /// Above `nowPlaying` -- a recording indicator is privacy-relevant and
    /// should outrank/interrupt music, not compete with it on equal footing.
    static let screenRecording = 15
    static let nowPlaying = 10
    static let airpods = 6
    static let battery = 5
}

/// Wraps the existing `NowPlayingCoordinator` as a `LiveActivitySource`,
/// per the design spec's migration note: `NowPlayingCoordinator` itself
/// is not rewritten, just wrapped.
final class NowPlayingLiveActivitySource: LiveActivitySource {
    let id = "nowPlaying"
    let priority = NotchLiveActivityPriority.nowPlaying

    private let notchHeight: CGFloat

    init(coordinator: NowPlayingCoordinator, notchHeight: CGFloat) {
        self.notchHeight = notchHeight
        self.coordinator = coordinator
    }

    private let coordinator: NowPlayingCoordinator

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        coordinator.$current
            .map { [notchHeight] info -> LiveActivityContent? in
                guard let info, info.isPlaying else { return nil }
                return NowPlayingActivityContent(info: info, notchHeight: notchHeight)
            }
            .eraseToAnyPublisher()
    }
}
