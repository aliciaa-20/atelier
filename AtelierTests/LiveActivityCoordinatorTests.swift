import Combine
import SwiftUI
import Testing
@testable import Atelier

private struct FakeContent: LiveActivityContent {
    let id: String
    func pillView() -> AnyView { AnyView(EmptyView()) }
    func peekView() -> AnyView { AnyView(EmptyView()) }
}

private final class FakeSource: LiveActivitySource {
    let id: String
    let priority: Int
    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)

    init(id: String, priority: Int) {
        self.id = id
        self.priority = priority
    }

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    func publish(contentID: String?) {
        subject.send(contentID.map { FakeContent(id: $0) })
    }
}

@MainActor
struct LiveActivityCoordinatorTests {
    @Test func topContentIsNilWithNothingPublished() {
        let source = FakeSource(id: "battery", priority: 1)
        let coordinator = LiveActivityCoordinator(sources: [source])
        #expect(coordinator.topContent == nil)
        #expect(coordinator.hasContent == false)
    }

    @Test func publishingContentBecomesTopContent() {
        let source = FakeSource(id: "battery", priority: 1)
        let coordinator = LiveActivityCoordinator(sources: [source])
        source.publish(contentID: "battery:low")
        #expect(coordinator.topContent?.id == "battery:low")
        #expect(coordinator.hasContent == true)
    }

    @Test func higherPrioritySourceWinsTopContent() {
        let low = FakeSource(id: "battery", priority: 1)
        let high = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "battery:low")
        high.publish(contentID: "trackA")
        #expect(coordinator.topContent?.id == "trackA")
    }

    @Test func withdrawingTopContentFallsBackToNextSource() {
        let low = FakeSource(id: "battery", priority: 1)
        let high = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "battery:low")
        high.publish(contentID: "trackA")
        high.publish(contentID: nil)
        #expect(coordinator.topContent?.id == "battery:low")
    }

    @Test func identityChangedFiresOnDifferentContentID() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: "trackA")
        source.publish(contentID: "trackB")
        #expect(fireCount == 2) // nil -> trackA, trackA -> trackB
        cancellable.cancel()
    }

    @Test func identityChangedDoesNotFireForNilTransition() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        source.publish(contentID: "trackA")
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: nil)
        #expect(fireCount == 0)
        cancellable.cancel()
    }

    /// Pausing then resuming the *same* track makes the source publish
    /// nil (pause) and then the same id again (resume) -- `lastContentID`
    /// must survive the nil publish so the resume doesn't look like a
    /// new track. Regression test for the double-`identityChanged`-fire
    /// bug found in review of Task 6.
    @Test func identityChangedDoesNotFireOnResumeOfSameTrackAfterPause() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        source.publish(contentID: "trackA")
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: nil) // pause
        source.publish(contentID: "trackA") // resume, same track
        #expect(fireCount == 0)
        cancellable.cancel()
    }
}
