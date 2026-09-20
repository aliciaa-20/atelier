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
}

struct NotchPageAdvancedTests {
    @Test func advancesForwardToShelf() {
        #expect(NotchPage.home.advanced(by: 1) == .shelf)
    }

    @Test func advancesBackwardToHome() {
        #expect(NotchPage.shelf.advanced(by: -1) == .home)
    }

    @Test func doesNotWrapPastTheLastPage() {
        #expect(NotchPage.shelf.advanced(by: 1) == nil)
    }

    @Test func doesNotWrapPastTheFirstPage() {
        #expect(NotchPage.home.advanced(by: -1) == nil)
    }

    @Test func respectsAFilteredPageList() {
        // Shelf disabled in Settings -- only Home is a valid destination.
        #expect(NotchPage.home.advanced(by: 1, in: [.home]) == nil)
    }
}
