import Foundation

/// Polls the now-playing source and republishes its latest result. Polls
/// once a second idle; the expanded player's scrubber needs smoother
/// updates, so `setExpanded(true)` switches to a 0.25s interval while it's
/// visible and back to 1s once it's not.
///
/// A 1s idle poll means a track change (and the peek it should trigger) can
/// lag up to a second behind reality. Spotify posts a distributed
/// notification on every playback change, which boring.notch's
/// `SpotifyController` uses to refresh immediately rather than waiting on
/// its own poll tick — same fix here, as an immediate-refresh fast path
/// alongside the existing poll loop, not a replacement for it.
@MainActor
final class NowPlayingCoordinator: ObservableObject {
    @Published private(set) var current: NowPlayingInfo?

    private static let idleInterval = Duration.seconds(1)
    private static let expandedInterval = Duration.milliseconds(250)
    private static let spotifyPlaybackStateChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")

    private let source: NowPlayingSource
    private var pollTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var interval = NowPlayingCoordinator.idleInterval

    init(source: NowPlayingSource = SpotifySource()) {
        self.source = source
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                current = await source.fetch()
                try? await Task.sleep(for: interval)
            }
        }

        notificationTask?.cancel()
        notificationTask = Task {
            let notifications = DistributedNotificationCenter.default()
                .notifications(named: Self.spotifyPlaybackStateChanged)
            for await _ in notifications {
                current = await source.fetch()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        notificationTask?.cancel()
        notificationTask = nil
    }

    func setExpanded(_ expanded: Bool) {
        interval = expanded ? Self.expandedInterval : Self.idleInterval
    }

    func playPause() async { await source.playPause() }
    func next() async { await source.next() }
    func previous() async { await source.previous() }
    func seek(to time: TimeInterval) async { await source.seek(to: time) }
    func toggleShuffle() async { await source.toggleShuffle() }
}
