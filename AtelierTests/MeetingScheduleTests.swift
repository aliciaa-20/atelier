import Foundation
import Testing
@testable import Atelier

struct MeetingScheduleTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func meeting(
        _ id: String = "a", startOffset: TimeInterval = 600, link: URL? = URL(string: "https://zoom.us/j/1"),
        allDay: Bool = false, cancelled: Bool = false, declined: Bool = false
    ) -> MeetingCandidate {
        MeetingCandidate(
            id: id, title: "Standup", start: t0.addingTimeInterval(startOffset),
            end: t0.addingTimeInterval(startOffset + 1800), joinURL: link,
            isAllDay: allDay, isCancelled: cancelled, isDeclined: declined)
    }

    private func phase(_ c: [MeetingCandidate], at offset: TimeInterval, excluding: Set<String> = []) -> MeetingSnapshot? {
        MeetingSchedule.current(candidates: c, now: t0.addingTimeInterval(offset), excluding: excluding)
    }

    @Test func nothingBeforeTheLeadWindow() {
        // start at +600; window opens at +480
        #expect(phase([meeting()], at: 479) == nil)
    }

    @Test func imminentFromExactlyTwoMinutesBefore() {
        #expect(phase([meeting()], at: 480)?.phase == .imminent)
        #expect(phase([meeting()], at: 599)?.phase == .imminent)
    }

    @Test func startedFromTheStartUntilFiveMinutesAfter() {
        #expect(phase([meeting()], at: 600)?.phase == .started)
        #expect(phase([meeting()], at: 899)?.phase == .started)
    }

    @Test func expiredFiveMinutesAfterStart() {
        #expect(phase([meeting()], at: 900) == nil)
    }

    @Test func ignoresAllDayCancelledDeclinedAndLinkless() {
        let bad = [
            meeting("d", allDay: true), meeting("c", cancelled: true),
            meeting("x", declined: true), meeting("n", link: nil),
        ]
        #expect(phase(bad, at: 500) == nil)
    }

    @Test func overlapPicksNearestStart() {
        // now = +500: "old" started 180 s ago (still in grace), "soon" starts in 60 s.
        let old = meeting("old", startOffset: 320)
        let soon = meeting("soon", startOffset: 560)
        #expect(phase([old, soon], at: 500)?.meeting.id == "soon")
        #expect(phase([soon, old], at: 500)?.meeting.id == "soon")
    }

    // Review Focus 3: identical start times must not depend on array order.
    @Test func simultaneousStartsAreDeterministic() {
        let a = meeting("a"), b = meeting("b")
        #expect(phase([a, b], at: 500)?.meeting.id == "a")
        #expect(phase([b, a], at: 500)?.meeting.id == "a")
    }

    @Test func excludedMeetingYieldsToTheNext() {
        let first = meeting("first", startOffset: 560)
        let second = meeting("second", startOffset: 600)
        #expect(phase([first, second], at: 500, excluding: ["first"])?.meeting.id == "second")
    }

    // Review Focus 1: recurring occurrences share an event id; the occurrence
    // id must differ so joining one doesn't hide the next.
    @Test func occurrenceIDsDifferPerStart() {
        let d1 = Date(timeIntervalSinceReferenceDate: 100)
        let d2 = Date(timeIntervalSinceReferenceDate: 100 + 86_400)
        #expect(MeetingCandidate.occurrenceID(eventID: "E", start: d1)
            != MeetingCandidate.occurrenceID(eventID: "E", start: d2))
    }

    @Test func nextChangeIsTheEarliestFutureBoundary() {
        let c = [meeting(startOffset: 600)] // boundaries: 480, 600, 900
        func next(_ now: TimeInterval) -> TimeInterval? {
            MeetingSchedule.nextChange(candidates: c, now: t0.addingTimeInterval(now), excluding: [])
                .map { $0.timeIntervalSince(t0) }
        }
        #expect(next(0) == 480)
        #expect(next(480) == 600)   // strictly after now
        #expect(next(600) == 900)
        #expect(next(900) == nil)
    }

    @Test func nextChangeIgnoresIneligibleMeetings() {
        #expect(MeetingSchedule.nextChange(candidates: [meeting(declined: true)], now: t0, excluding: []) == nil)
    }
}
