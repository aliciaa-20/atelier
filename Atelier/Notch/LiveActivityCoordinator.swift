import Combine
import Foundation
import SwiftUI

/// Merges every `LiveActivitySource`'s content into a `LiveActivityStack`
/// and republishes two generic signals `NotchController` maps onto
/// `NotchState`'s existing event vocabulary (`.trackChanged`,
/// `.isPlayingChanged`, `.playbackToggled`) -- `NotchState.swift` itself
/// is not modified; it was already source-agnostic in effect. Simplified
/// relative to dynamicnotch's `NotchEngine` (no queueing, no
/// temporary-vs-persistent distinction, no dismiss/restore history) --
/// per the design spec, nothing here needs that yet.
@MainActor
final class LiveActivityCoordinator: ObservableObject {
    @Published private(set) var topContent: LiveActivityContent?
    @Published private(set) var hasContent = false
    /// A lower-priority source's content, shown briefly in the pill even
    /// while a higher-priority source (e.g. now-playing) is on top --
    /// otherwise something like Battery would be invisible for as long as
    /// music plays. Only `NotchRootView`'s `.pill` branch reads this; peek
    /// and expanded are untouched, so this never pops the bigger view,
    /// just briefly swaps what the small pill shows.
    @Published private(set) var interruptContent: LiveActivityContent?
    let identityChanged = PassthroughSubject<Void, Never>()

    private static let interruptDuration: Duration = .seconds(3)

    private var stack = LiveActivityStack()
    private var latestContent: [String: LiveActivityContent] = [:]
    /// The last id `identityChanged` fired for, keyed by *which source*
    /// owned `topContent` at the time -- not a single global field. A
    /// single shared field broke when a higher-priority source (Volume/
    /// Brightness) temporarily outranked a lower one (NowPlaying) and then
    /// cleared: the fallback to the still-unchanged lower source looked
    /// like a new identity, because the shared field had last been set to
    /// the higher source's own (freshly UUID'd every publish) id, not the
    /// lower source's stable one -- confirmed on-device as "volume/
    /// brightness peek flashes the now-playing view before closing."
    /// Per-source, only ever updated for whichever source is topID at the
    /// time (never cleared to nil), a pause/resume of the same track still
    /// doesn't re-fire: the entry for that source simply sits untouched
    /// while it's off the stack, same as the original single-field
    /// behavior this replaces.
    private var lastPeekedContentIDBySource: [String: String] = [:]
    /// Per-source last-seen content id (including nil, unlike the field
    /// above), independent of which source is on top -- this is what lets
    /// a source that's never on top still be noticed when its own content
    /// changes, to drive `interruptContent`.
    private var lastContentIDBySource: [String: String] = [:]
    private var interruptClearTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    /// Kept for `handle`'s stale-priority refresh below -- most sources'
    /// `priority` is a fixed `let`, but `VolumeSource`/`BrightnessSource`
    /// compute theirs from shared `SystemHUDOrder` state, which can change
    /// without *that* source publishing new content.
    private var sourcesByID: [String: LiveActivitySource] = [:]

    init(sources: [LiveActivitySource]) {
        for source in sources {
            sourcesByID[source.id] = source
            source.contentPublisher
                .receive(on: RunLoop.main)
                .sink { [weak self] content in
                    self?.handle(sourceID: source.id, priority: source.priority, content: content)
                }
                .store(in: &cancellables)
        }
    }

    private func handle(sourceID: String, priority: Int, content: LiveActivityContent?) {
        if let content {
            latestContent[sourceID] = content
            stack.upsert(id: sourceID, priority: priority)
        } else {
            latestContent.removeValue(forKey: sourceID)
            stack.remove(id: sourceID)
        }

        // A source's own `priority` can depend on shared external state
        // (e.g. `SystemHUDOrder`), not just its own content -- without
        // this, a still-active *other* source's stack entry keeps
        // whatever priority it had at ITS last publish, which can outlive
        // the event that should have superseded it. Confirmed on-device:
        // pressing volume while brightness was active left brightness
        // winning `LiveActivityStack`'s tie-break on a stale snapshot
        // until brightness's own next publish, not immediately.
        for otherID in latestContent.keys where otherID != sourceID {
            if let otherSource = sourcesByID[otherID] {
                stack.upsert(id: otherID, priority: otherSource.priority)
            }
        }

        topContent = stack.topID.flatMap { latestContent[$0] }

        // Compared against the *owning source's own* last-peeked id, not a
        // single shared field -- see `lastPeekedContentIDBySource`'s own
        // doc comment for why. Only ever updated for `stack.topID`, and
        // only when non-nil, so a pause/resume of the same track (which
        // removes it from the stack entirely while paused, see
        // `NowPlayingLiveActivitySource.contentPublisher`'s `isPlaying`
        // guard) leaves this source's entry untouched while it's off the
        // stack, then compares equal again on resume.
        let newContentID = topContent?.id
        if let newContentID, let topID = stack.topID {
            // Only peek-worthy content (peeksOnChange == true) fires
            // identityChanged -- ambient content like Battery becoming
            // top (or a different battery state arriving) should only
            // ever update the pill, never auto-pop a peek.
            if newContentID != lastPeekedContentIDBySource[topID], topContent?.peeksOnChange == true {
                identityChanged.send()
            }
            lastPeekedContentIDBySource[topID] = newContentID
        }

        hasContent = topContent != nil

        // Briefly interrupt the pill with a lower-priority source's
        // content when it changes, even though it isn't the current top
        // (the top content is already visible via `topContent` itself --
        // no need to interrupt for that). Auto-clears back to the real
        // top after `interruptDuration`.
        if let content, sourceID != stack.topID, lastContentIDBySource[sourceID] != content.id {
            interruptClearTask?.cancel()
            // Quick pop in, same speed as a peek opening; slower and more
            // damped going back out, same reasoning as hoverEnded's own
            // asymmetric treatment in NotchRootView -- retracting at the
            // same snappy speed it appeared with reads as abrupt.
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                interruptContent = content
            }
            interruptClearTask = Task { [weak self] in
                try? await Task.sleep(for: Self.interruptDuration)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.92)) {
                    self.interruptContent = nil
                }
            }
        }
        lastContentIDBySource[sourceID] = content?.id
    }
}
