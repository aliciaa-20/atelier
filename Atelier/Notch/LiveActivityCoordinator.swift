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
    private var lastContentID: String?
    /// Per-source last-seen content id, independent of `lastContentID`
    /// (which only tracks the *top* content's id) -- this is what lets a
    /// source that's never on top still be noticed when its own content
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

        // `lastContentID` is only ever updated to a non-nil id -- it is
        // NOT cleared when content disappears (e.g. a pause). That way a
        // pause/resume of the *same* track leaves `lastContentID`
        // pointing at that track's still-correct id, so the resume
        // publish sees `newContentID == lastContentID` and does not fire
        // `identityChanged` -- matching the pre-Task-6 `lastTrackKey`
        // behavior, which was likewise untouched by isPlaying transitions.
        // A genuinely different track appearing later still fires, since
        // its id differs from whatever stale id is still held here.
        //
        // Gated on `content != nil` -- this `handle` call's own publish,
        // not just whatever `topContent` ends up being. Without this, a
        // *removal* (Volume/Brightness's peek content self-clearing) that
        // causes `topContent` to fall through to some other
        // already-active source (NowPlaying, still playing underneath)
        // fired `identityChanged` for NowPlaying's id, since it differed
        // from `lastContentID` (which was Volume's) -- re-triggering a
        // brand-new peek for NowPlaying right as Volume/Brightness's own
        // peek was closing. Confirmed on-device: "adjusting volume shows
        // the now-playing peek, then closes." NowPlaying's content didn't
        // actually change; only the stack's top pointer moved because
        // something *else* was removed, and a removal should never be
        // read as new content arriving.
        let newContentID = topContent?.id
        if content != nil, let newContentID {
            // Only peek-worthy content (peeksOnChange == true) fires
            // identityChanged -- ambient content like Battery becoming
            // top (or a different battery state arriving) should only
            // ever update the pill, never auto-pop a peek.
            if newContentID != lastContentID, topContent?.peeksOnChange == true {
                identityChanged.send()
            }
            lastContentID = newContentID
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
