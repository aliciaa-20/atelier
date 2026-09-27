import Foundation

/// Wraps several `NowPlayingSource`s and presents them as one, so
/// `NowPlayingCoordinator` doesn't need to know more than one app can be
/// playing music. Only queries a wrapped source when it's actually running
/// (each source's own `isAvailable` check), so having Apple Music installed
/// but not open costs nothing extra over the Spotify-only baseline.
///
/// A class (not a struct) because it tracks which source is "active" across
/// polls (`NowPlayingArbiter`'s sticky tie-break) and transport commands need
/// that same state.
final class MultiNowPlayingSource: NowPlayingSource {
    private let sources: [(id: String, source: any NowPlayingSource)]
    private var activeID: String?

    init(sources: [any NowPlayingSource]) {
        self.sources = sources.map { (String(describing: type(of: $0)), $0) }
    }

    var isAvailable: Bool {
        sources.contains { $0.source.isAvailable }
    }

    func fetch() async -> NowPlayingInfo? {
        var infos: [String: NowPlayingInfo?] = [:]
        for entry in sources where entry.source.isAvailable {
            infos[entry.id] = await entry.source.fetch()
        }

        let candidates = sources.map { NowPlayingArbiter.Candidate(sourceID: $0.id, info: infos[$0.id] ?? nil) }
        activeID = NowPlayingArbiter.choose(candidates: candidates, previousActiveID: activeID)
        guard let activeID else { return nil }
        return infos[activeID] ?? nil
    }

    private var activeSource: (any NowPlayingSource)? {
        sources.first { $0.id == activeID }?.source
    }

    func playPause() async { await activeSource?.playPause() }
    func next() async { await activeSource?.next() }
    func previous() async { await activeSource?.previous() }
    func seek(to time: TimeInterval) async { await activeSource?.seek(to: time) }
    func toggleShuffle() async { await activeSource?.toggleShuffle() }
}
