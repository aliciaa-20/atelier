import Testing
@testable import Atelier

struct NotchPageTransitionTests {
    @Test func shelfStateForcesShelfPageRegardlessOfCurrentPage() {
        let result = NotchPageTransition.page(for: .shelf, currentPage: .home)

        #expect(result == .shelf)
    }

    @Test func collapsedResetsToHomeEvenIfShelfWasSelected() {
        let result = NotchPageTransition.page(for: .collapsed, currentPage: .shelf)

        #expect(result == .home)
    }

    @Test func pillResetsToHomeEvenIfShelfWasSelected() {
        let result = NotchPageTransition.page(for: .pill, currentPage: .shelf)

        #expect(result == .home)
    }

    @Test func expandedPreservesCurrentPage() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .shelf)

        #expect(result == .shelf)
    }

    @Test func peekingPreservesCurrentPage() {
        let result = NotchPageTransition.page(for: .peeking, currentPage: .shelf)

        #expect(result == .shelf)
    }

    @Test func expandedPreservesHomePage() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .home)

        #expect(result == .home)
    }

    @Test func peekingPreservesHomePage() {
        let result = NotchPageTransition.page(for: .peeking, currentPage: .home)

        #expect(result == .home)
    }

    @Test func collapsedResetsToHomeEvenIfCameraWasSelected() {
        let result = NotchPageTransition.page(for: .collapsed, currentPage: .camera)

        #expect(result == .home)
    }

    @Test func expandedPreservesCameraPage() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .camera)

        #expect(result == .camera)
    }

    @Test func collapsedResetsToTheFirstTabWhenHomeIsNotFirst() {
        let result = NotchPageTransition.page(for: .collapsed, currentPage: .shelf, firstPage: .camera)

        #expect(result == .camera)
    }

    @Test func pillResetsToTheFirstTabWhenHomeIsNotFirst() {
        let result = NotchPageTransition.page(for: .pill, currentPage: .home, firstPage: .camera)

        #expect(result == .camera)
    }

    @Test func expandedStillPreservesTheCurrentPageWhateverTheFirstTab() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .shelf, firstPage: .camera)

        #expect(result == .shelf)
    }

    @Test func shelfStateStillForcesShelfWhateverTheFirstTab() {
        let result = NotchPageTransition.page(for: .shelf, currentPage: .home, firstPage: .camera)

        #expect(result == .shelf)
    }

    @Test func openingFromCollapsedGoesToTheCurrentFirstTab() {
        // The order can change while the notch is collapsed; the page must
        // be picked when it opens, not remembered from when it closed.
        let result = NotchPageTransition.page(for: .expanded, currentPage: .home, firstPage: .camera, previousState: .collapsed)

        #expect(result == .camera)
    }

    @Test func openingFromPillGoesToTheCurrentFirstTab() {
        let result = NotchPageTransition.page(for: .peeking, currentPage: .home, firstPage: .camera, previousState: .pill)

        #expect(result == .camera)
    }

    @Test func peekingToExpandedKeepsTheTabTheUserIsOn() {
        let result = NotchPageTransition.page(for: .expanded, currentPage: .shelf, firstPage: .camera, previousState: .peeking)

        #expect(result == .shelf)
    }

    @Test func aCurrentPageThatWasDisabledFallsBackToTheFirstTab() {
        let result = NotchPageTransition.page(
            for: .expanded, currentPage: .camera, firstPage: .home,
            previousState: .expanded, enabledPages: [.home, .calendar]
        )

        #expect(result == .home)
    }
}
