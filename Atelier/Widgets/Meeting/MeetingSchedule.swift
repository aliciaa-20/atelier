import Foundation

/// One calendar event as Meeting Join needs it -- a plain value so this file
/// (and its tests) never touch `EKEvent`. Foundation only, like `CalendarMath`.
struct MeetingCandidate: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?
    let isAllDay: Bool
    let isCancelled: Bool
    let isDeclined: Bool

    /// Recurring events share one `eventIdentifier` across occurrences, so
    /// the start date is part of the identity -- joining today's standup must
    /// not hide tomorrow's.
    static func occurrenceID(eventID: String, start: Date) -> String {
        "\(eventID)|\(Int(start.timeIntervalSinceReferenceDate))"
    }
}

enum MeetingPhase: Equatable {
    /// Within `leadTime` before the start.
    case imminent
    /// From the start until `graceAfterStart` later.
    case started
}

struct MeetingSnapshot: Equatable {
    let meeting: MeetingCandidate
    let phase: MeetingPhase
}

/// Decides which meeting (if any) the notch should be offering to join, and
/// when that answer will next change -- so the source can arm one timer
/// instead of polling.
enum MeetingSchedule {
    static let leadTime: TimeInterval = 120
    static let graceAfterStart: TimeInterval = 300

    /// Ignores all-day, cancelled, declined, link-less and `excluding` events.
    /// If several are in their window, the one whose start is nearest `now`
    /// wins; ties break by `id` so the result never depends on array order.
    static func current(candidates: [MeetingCandidate], now: Date, excluding: Set<String>) -> MeetingSnapshot? {
        let inWindow = eligible(candidates, excluding: excluding).filter {
            now >= $0.start.addingTimeInterval(-leadTime) && now < $0.start.addingTimeInterval(graceAfterStart)
        }
        guard let pick = inWindow.min(by: { lhs, rhs in
            let l = abs(lhs.start.timeIntervalSince(now)), r = abs(rhs.start.timeIntervalSince(now))
            return l != r ? l < r : lhs.id < rhs.id
        }) else { return nil }
        return MeetingSnapshot(meeting: pick, phase: now < pick.start ? .imminent : .started)
    }

    /// The earliest boundary strictly after `now` across all eligible meetings.
    static func nextChange(candidates: [MeetingCandidate], now: Date, excluding: Set<String>) -> Date? {
        eligible(candidates, excluding: excluding)
            .flatMap { [$0.start.addingTimeInterval(-leadTime), $0.start, $0.start.addingTimeInterval(graceAfterStart)] }
            .filter { $0 > now }
            .min()
    }

    private static func eligible(_ candidates: [MeetingCandidate], excluding: Set<String>) -> [MeetingCandidate] {
        candidates.filter {
            $0.joinURL != nil && !$0.isAllDay && !$0.isCancelled && !$0.isDeclined && !excluding.contains($0.id)
        }
    }
}
