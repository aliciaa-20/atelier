import Testing
@testable import Atelier

struct TabOrderTests {
    private let all = Set(NotchPage.allCases)

    @Test func emptyStoredOrderGivesTheDefaultOrder() {
        let result = TabOrder.resolve(stored: [], enabled: all)

        #expect(result == [.home, .shelf, .systemMonitor, .calendar, .camera, .teleprompter])
    }

    @Test func followsTheStoredOrder() {
        let result = TabOrder.resolve(stored: ["camera", "calendar", "shelf", "systemMonitor"], enabled: all)

        #expect(result == [.home, .camera, .calendar, .shelf, .systemMonitor, .teleprompter])
    }

    @Test func homeCanBeReorderedLikeAnyOtherTab() {
        let result = TabOrder.resolve(stored: ["camera", "home", "shelf"], enabled: all)

        #expect(result == [.camera, .home, .shelf, .systemMonitor, .calendar, .teleprompter])
    }

    @Test func homeStaysFirstWhenTheStoredOrderDoesNotMentionIt() {
        // An order saved before Home was movable lists only the other pages.
        let result = TabOrder.resolve(stored: ["camera", "shelf"], enabled: all)

        #expect(result.first == .home)
    }

    @Test func homeCannotBeDisabled() {
        let result = TabOrder.resolve(stored: [], enabled: [.camera])

        #expect(result == [.home, .camera])
    }

    @Test func disabledPagesAreSkipped() {
        let enabled: Set<NotchPage> = [.home, .camera]

        let result = TabOrder.resolve(stored: ["shelf", "camera"], enabled: enabled)

        #expect(result == [.home, .camera])
    }

    @Test func unknownNamesAndDuplicatesAreIgnored() {
        let result = TabOrder.resolve(stored: ["bogus", "camera", "camera", "shelf"], enabled: all)

        #expect(result == [.home, .camera, .shelf, .systemMonitor, .calendar, .teleprompter])
    }

    @Test func aPageMissingFromTheStoredListIsAppendedInDefaultOrder() {
        let result = TabOrder.resolve(stored: ["camera", "shelf"], enabled: all)

        #expect(result == [.home, .camera, .shelf, .systemMonitor, .calendar, .teleprompter])
    }

    @Test func aDisabledPageKeepsItsSavedPositionWhenReEnabled() {
        let stored = ["camera", "shelf", "systemMonitor", "calendar"]

        let whileDisabled = TabOrder.resolve(stored: stored, enabled: all.subtracting([.camera]))
        let afterReEnable = TabOrder.resolve(stored: stored, enabled: all)

        #expect(whileDisabled == [.home, .shelf, .systemMonitor, .calendar, .teleprompter])
        #expect(afterReEnable == [.home, .camera, .shelf, .systemMonitor, .calendar, .teleprompter])
    }

    @Test func noEnabledPagesStillResolvesToHome() {
        let result = TabOrder.resolve(stored: ["camera", "shelf"], enabled: [])

        #expect(result == [.home])
    }
}
