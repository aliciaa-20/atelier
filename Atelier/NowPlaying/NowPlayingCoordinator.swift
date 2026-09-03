import Foundation

/// Polls the now-playing source and republishes its latest result. Polls
/// once a second idle; the expanded player's scrubber needs smoother
/// updates, so `setExpanded(true)` switches to a 0.25s interval while it's
/// visible and back to 1s once it's not.
@MainActor
final class NowPlayingCoordinator: ObservableObject {
    @Published private(set) var current: NowPlayingInfo?

    private static let idleInterval = Duration.seconds(1)
    private static let expandedInterval = Duration.milliseconds(250)

    private let source: NowPlayingSource
    private var pollTask: Task<Void, Never>?
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
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
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
