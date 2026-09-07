import Combine
import Foundation

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
    let identityChanged = PassthroughSubject<Void, Never>()

    private var stack = LiveActivityStack()
    private var latestContent: [String: LiveActivityContent] = [:]
    private var lastContentID: String?
    private var cancellables: Set<AnyCancellable> = []

    init(sources: [LiveActivitySource]) {
        for source in sources {
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
        let newContentID = topContent?.id
        if let newContentID {
            if newContentID != lastContentID {
                identityChanged.send()
            }
            lastContentID = newContentID
        }

        hasContent = topContent != nil
    }
}
