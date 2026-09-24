import Foundation

/// Pure week/day arithmetic for the Calendar tab -- Foundation only, like
/// `NotchGeometry`, so it's testable without EventKit or a real calendar.
/// Takes `Calendar` as a parameter (not `.current` inside) so a test can
/// pin the locale's first weekday.
enum CalendarMath {
    /// Midnight at the start of the week containing `date`, honouring the
    /// calendar's `firstWeekday` (Sunday in the US, Monday in much of Europe).
    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    /// The seven day-start dates of the week beginning at `weekStart`.
    static func days(inWeekStarting weekStart: Date, calendar: Calendar) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// `weekStart` moved by whole weeks (negative = earlier).
    static func shift(weekStart: Date, byWeeks weeks: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart
    }

    /// Whether an event spanning `start..<end` touches the day starting at
    /// `day`. An all-day or multi-day event counts on every day it covers;
    /// an event ending exactly at midnight does not spill into the next day.
    static func event(start: Date, end: Date, occursOn day: Date, calendar: Calendar) -> Bool {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return start < nextDay && (end > day || start == day)
    }
}
