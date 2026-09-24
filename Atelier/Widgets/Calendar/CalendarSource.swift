import CoreGraphics
import EventKit
import Foundation

/// One event as the Calendar tab needs it -- a plain value so views never
/// touch `EKEvent` (and its store-lifetime rules) directly.
struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: CGColor?
}

/// One calendar in the tab's filter menu.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    var isEnabled: Bool
}

/// Read-only EventKit feed for `NotchPage.calendar`. Not a
/// `LiveActivitySource` -- there is no pill for it (yet), so it just owns
/// state for the tab, like `ShelfStore`.
///
/// Lightweight by design (CLAUDE.md): nothing runs until `activate()` --
/// called when the tab is first shown -- so the permission prompt only
/// appears when the user actually opens Calendar. After that it refreshes
/// on `.EKEventStoreChanged` (push), never on a timer.
@MainActor
final class CalendarSource: ObservableObject {
    enum Access: Equatable {
        case notDetermined
        case granted
        case denied
    }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var weekStart: Date
    @Published var selectedDay: Date
    /// How far past `selectedDay` the finger is toward the next/previous day
    /// (-0.5...0.5) during a scroll-style swipe; 0 at rest. Drives the moving
    /// indicator in `CalendarPageView`.
    @Published private(set) var scrubFraction: CGFloat = 0
    /// Set for the duration of a scroll-style swipe: the day it started on.
    @Published private(set) var scrubBaseDay: Date?
    var isScrubbing: Bool { scrubBaseDay != nil }
    /// The day that drives the panel's height. Frozen at the swipe's start
    /// day while scrubbing -- otherwise the notch would resize on every day
    /// crossed and jitter -- and released when the finger lifts.
    var layoutDay: Date { scrubBaseDay ?? selectedDay }

    private let store = EKEventStore()
    private var calendar: Calendar { .current }
    private var isActivated = false
    // Same `nonisolated(unsafe)` reasoning as `SystemMonitorSource.pollTask`:
    // `deinit` is nonisolated, and this is only touched from `activate()`
    // (MainActor) and `deinit`.
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = today
        weekStart = CalendarMath.startOfWeek(containing: today, calendar: .current)
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    /// Idempotent. Requests access if needed, then loads the visible week
    /// and starts listening for changes.
    func activate() {
        guard !isActivated else { return }
        isActivated = true
        Task { await resolveAccess() }
    }

    /// Re-check after the user flips the switch in System Settings.
    func recheckAccess() {
        Task { await resolveAccess() }
    }

    func setCalendar(_ id: String, enabled: Bool) {
        var hidden = AtelierSettings.hiddenCalendarIDs
        if enabled { hidden.remove(id) } else { hidden.insert(id) }
        AtelierSettings.hiddenCalendarIDs = hidden
        loadEvents()
    }

    /// The tab always opens on today's date, not wherever it was left.
    func resetToToday() {
        let today = calendar.startOfDay(for: Date())
        let newWeekStart = CalendarMath.startOfWeek(containing: today, calendar: calendar)
        let weekChanged = newWeekStart != weekStart
        selectedDay = today
        weekStart = newWeekStart
        if weekChanged { loadEvents() }
    }

    /// Called on every update of a scroll-style swipe with the gesture's total
    /// horizontal distance. Event-driven: only touches EventKit when the
    /// visible week actually changes.
    func scrub(totalDX: CGFloat) {
        if scrubBaseDay == nil { scrubBaseDay = selectedDay }
        guard let base = scrubBaseDay else { return }
        let resolved = CalendarScrub.resolve(totalDX: totalDX)
        let day = calendar.date(byAdding: .day, value: resolved.dayOffset, to: base) ?? base
        if day != selectedDay {
            selectedDay = day
            let newWeekStart = CalendarMath.startOfWeek(containing: day, calendar: calendar)
            if newWeekStart != weekStart {
                weekStart = newWeekStart
                loadEvents()
            }
        }
        scrubFraction = resolved.fraction
    }

    func endScrub() {
        scrubBaseDay = nil
        scrubFraction = 0
    }

    func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
    }

    func shiftWeek(by weeks: Int) {
        weekStart = CalendarMath.shift(weekStart: weekStart, byWeeks: weeks, calendar: calendar)
        // Keep the same weekday selected in the new week.
        selectedDay = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDay) ?? weekStart
        loadEvents()
    }

    /// Events touching `day`, all-day first then by start time.
    func events(on day: Date) -> [CalendarEventItem] {
        events
            .filter { CalendarMath.event(start: $0.start, end: $0.end, occursOn: day, calendar: calendar) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    private func resolveAccess() async {
        switch CalendarPermission.status {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
        default:
            access = .denied
        }
        if access == .granted {
            observeChanges()
            loadEvents()
        }
    }

    private func observeChanges() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.loadEvents() }
        }
    }

    private func loadEvents() {
        guard access == .granted,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return }
        let hidden = AtelierSettings.hiddenCalendarIDs
        let all = store.calendars(for: .event)
        calendars = all
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, isEnabled: !hidden.contains($0.calendarIdentifier)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let enabled = all.filter { !hidden.contains($0.calendarIdentifier) }
        // Empty array is ambiguous to EventKit (nil means "all"), so short-circuit.
        guard !enabled.isEmpty else { events = []; return }
        let predicate = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: enabled)
        events = store.events(matching: predicate).map {
            CalendarEventItem(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title ?? "Untitled",
                start: $0.startDate,
                end: $0.endDate,
                isAllDay: $0.isAllDay,
                color: $0.calendar.cgColor
            )
        }
    }
}
