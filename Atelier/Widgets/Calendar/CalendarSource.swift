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
    @Published private(set) var weekStart: Date
    @Published var selectedDay: Date

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
        let predicate = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: nil)
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
