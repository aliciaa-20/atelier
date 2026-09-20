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
    /// `LiveActivityCoordinator` now applies `.receive(on: RunLoop.main)`
    /// to every source (Fix 2 in the final review pass, so a source that
    /// publishes off the main actor -- `BatterySource`, in this codebase --
    /// can't corrupt `@Published` state). That makes delivery asynchronous
    /// even when the publish happens on the main thread, so tests need to
    /// pump the main run loop briefly after each `publish()` before
    /// asserting on the coordinator's state.
    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

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
        drainMainRunLoop()
        #expect(coordinator.topContent?.id == "battery:low")
        #expect(coordinator.hasContent == true)
    }

    @Test func higherPrioritySourceWinsTopContent() {
        let low = FakeSource(id: "battery", priority: 1)
        let high = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "battery:low")
        high.publish(contentID: "trackA")
        drainMainRunLoop()
        #expect(coordinator.topContent?.id == "trackA")
    }

    @Test func withdrawingTopContentFallsBackToNextSource() {
        let low = FakeSource(id: "battery", priority: 1)
        let high = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "battery:low")
        high.publish(contentID: "trackA")
        high.publish(contentID: nil)
        drainMainRunLoop()
        #expect(coordinator.topContent?.id == "battery:low")
    }

    @Test func identityChangedFiresOnDifferentContentID() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: "trackA")
        source.publish(contentID: "trackB")
        drainMainRunLoop()
        #expect(fireCount == 2) // nil -> trackA, trackA -> trackB
        cancellable.cancel()
    }

    @Test func identityChangedDoesNotFireForNilTransition() {
        let source = FakeSource(id: "nowPlaying", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [source])
        source.publish(contentID: "trackA")
        drainMainRunLoop()
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: nil)
        drainMainRunLoop()
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
        drainMainRunLoop()
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        source.publish(contentID: nil) // pause
        source.publish(contentID: "trackA") // resume, same track
        drainMainRunLoop()
        #expect(fireCount == 0)
        cancellable.cancel()
    }

    /// Regression test: a higher-priority source withdrawing (Volume's
    /// peek content self-clearing) must not fire `identityChanged` for
    /// whatever lower-priority source (NowPlaying) becomes top as a
    /// result -- that source's own content didn't change, only the
    /// stack's top pointer moved because something else was removed.
    /// Confirmed on-device as "adjusting volume shows the now-playing
    /// peek, then closes" before this fix.
    @Test func identityChangedDoesNotFireWhenFallbackContentBecomesTop() {
        let low = FakeSource(id: "nowPlaying", priority: 1)
        let high = FakeSource(id: "volume", priority: 10)
        let coordinator = LiveActivityCoordinator(sources: [low, high])
        low.publish(contentID: "trackA")
        high.publish(contentID: "volume:50")
        drainMainRunLoop()
        var fireCount = 0
        let cancellable = coordinator.identityChanged.sink { fireCount += 1 }
        high.publish(contentID: nil) // Volume's peek content self-clears
        drainMainRunLoop()
        #expect(coordinator.topContent?.id == "trackA")
        #expect(fireCount == 0)
        cancellable.cancel()
    }
}
