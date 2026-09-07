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

        let newContentID = topContent?.id
        if let newContentID, newContentID != lastContentID {
            identityChanged.send()
        }
        lastContentID = newContentID

        hasContent = topContent != nil
    }
}
