import Foundation

protocol NowPlayingSource {
    /// Whether the underlying app is actually running. Must be checked
    /// before scripting it — querying an app that isn't running launches it
    /// (CLAUDE.md invariant 2).
    var isAvailable: Bool { get }
    func fetch() async -> NowPlayingInfo?
    func playPause() async
    func next() async
    func previous() async
    func seek(to time: TimeInterval) async
}
