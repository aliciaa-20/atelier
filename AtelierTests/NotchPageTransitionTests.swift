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
}
