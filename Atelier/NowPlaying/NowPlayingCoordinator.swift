import Foundation

/// Polls the now-playing source and republishes its latest result once a
/// second. Phase 3 proves this pipeline end-to-end (AppleScript → parsing →
/// here); Phase 4 wires the output into the real player UI and adds a faster
/// poll rate while expanded, once there's a scrubber that needs it.
@MainActor
final class NowPlayingCoordinator: ObservableObject {
    @Published private(set) var current: NowPlayingInfo?

    private let source: NowPlayingSource
    private var pollTask: Task<Void, Never>?

    init(source: NowPlayingSource = SpotifySource()) {
        self.source = source
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                current = await source.fetch()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}
