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
    /// Above `nowPlaying` -- picking a color is a deliberate, brief user
    /// action and should interrupt whatever's currently showing rather
    /// than wait its turn behind it, but it's not privacy-relevant like
    /// `screenRecording`, so it doesn't outrank that.
    static let colorPicker = 11
    static let nowPlaying = 10
    static let airpods = 6
    static let battery = 5
    /// Lowest of all -- the least urgent ambient signal in the app (see
    /// `SystemMonitorActivityContent`'s own doc comment). Only reaches the
    /// pill when nothing else, including Battery, has anything to show.
    static let systemMonitor = 4
}

/// Wraps the existing `NowPlayingCoordinator` as a `LiveActivitySource`,
/// per the design spec's migration note: `NowPlayingCoordinator` itself
/// is not rewritten, just wrapped.
final class NowPlayingLiveActivitySource: LiveActivitySource {
    let id = "nowPlaying"
    let priority = NotchLiveActivityPriority.nowPlaying

    private let notchHeight: CGFloat
    private let audioTap: AudioTap

    init(coordinator: NowPlayingCoordinator, notchHeight: CGFloat, audioTap: AudioTap) {
        self.notchHeight = notchHeight
        self.coordinator = coordinator
        self.audioTap = audioTap
    }

    private let coordinator: NowPlayingCoordinator

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        coordinator.$current
            .map { [notchHeight, audioTap] info -> LiveActivityContent? in
                guard let info, info.isPlaying else { return nil }
                return NowPlayingActivityContent(info: info, notchHeight: notchHeight, audioTap: audioTap)
            }
            .eraseToAnyPublisher()
    }
}
