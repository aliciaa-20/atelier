import Foundation

/// Decides which of several `NowPlayingSource`s should be treated as "the"
/// current source, without ever needing to know how to talk to any of them.
/// Sticky on ties (both/neither playing) so a track pausing for a beat on one
/// app doesn't flap the UI over to the other.
enum NowPlayingArbiter {
    struct Candidate {
        let sourceID: String
        let info: NowPlayingInfo?
    }

    static func choose(candidates: [Candidate], previousActiveID: String?) -> String? {
        let available = candidates.filter { $0.info != nil }
        guard !available.isEmpty else { return nil }

        let playing = available.filter { $0.info?.isPlaying == true }
        if playing.count == 1 {
            return playing[0].sourceID
        }

        if let previousActiveID, available.contains(where: { $0.sourceID == previousActiveID }) {
            return previousActiveID
        }

        return available[0].sourceID
    }
}
