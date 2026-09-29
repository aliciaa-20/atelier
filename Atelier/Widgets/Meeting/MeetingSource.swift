import AppKit
import Combine
import EventKit
import Foundation

/// Publishes Meeting Join's pill/peek. Own `EKEventStore` (calendar access is
/// app-wide, so no second prompt) and independent of `CalendarSource`'s lazy
/// tab lifecycle. Lightweight by design (CLAUDE.md): while disabled nothing
/// is observed or scheduled; while enabled it holds ONE timer, armed for the
/// next phase boundary, plus push observers -- no polling. Timer-fire, store
/// changes, wake and clock changes all funnel into `reload()`.
/// Reference: leits/MeetingBar (Apache-2.0) for what event fields carry links.
@MainActor
final class MeetingSource: LiveActivitySource {
    let id = "meeting"
    let priority = NotchLiveActivityPriority.meeting

    private let subject = CurrentValueSubject<LiveActivityContent?, Never>(nil)
    private let notchHeight: CGFloat
    private let store = EKEventStore()
    private var candidates: [MeetingCandidate] = []
    private var joinedIDs: Set<String> = []
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private(set) var isRunning = false

    var contentPublisher: AnyPublisher<LiveActivityContent?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(notchHeight: CGFloat) {
        self.notchHeight = notchHeight
    }

    /// Idempotent -- `NotchController.applyLiveSettings` calls this on every
    /// UserDefaults change.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isRunning else { return }
        enabled ? start() : stop()
    }

    private func start() {
        // Never prompt from here -- the Settings toggle owns the request. If
        // access isn't granted, stay stopped so a later setEnabled(true) retries.
        guard CalendarPermission.status == .fullAccess else { return }
        isRunning = true
        observe(.EKEventStoreChanged, on: .default, object: store)
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter)
        observe(.NSSystemClockDidChange, on: .default)
        reload()
    }

    private func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        candidates = []
        joinedIDs = []
        subject.send(nil)
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, object: AnyObject? = nil) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        observers.append((center, token))
    }

    private func reload() {
        guard isRunning else { return }
        // Access revoked while enabled -> clear, don't leave a stale Join.
        guard CalendarPermission.status == .fullAccess else {
            candidates = []
            refresh()
            return
        }
        let now = Date()
        let hidden = AtelierSettings.hiddenCalendarIDs
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            candidates = []
            refresh()
            return
        }
        // From "still inside the grace window" to a few hours ahead; the timer
        // re-runs this at least hourly so the horizon never goes stale.
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-MeetingSchedule.graceAfterStart),
            end: now.addingTimeInterval(6 * 3600),
            calendars: calendars)
        candidates = store.events(matching: predicate).map { event in
            MeetingCandidate(
                id: MeetingCandidate.occurrenceID(eventID: event.eventIdentifier ?? event.title ?? "?", start: event.startDate),
                title: event.title ?? "Meeting",
                start: event.startDate,
                end: event.endDate,
                joinURL: MeetingLinkParser.joinURL(url: event.url, location: event.location, notes: event.notes),
                isAllDay: event.isAllDay,
                isCancelled: event.status == .canceled,
                isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }
        refresh()
    }

    /// Republish the current answer and re-arm the single timer.
    private func refresh() {
        let now = Date()
        if let snapshot = MeetingSchedule.current(candidates: candidates, now: now, excluding: joinedIDs),
           let url = snapshot.meeting.joinURL {
            subject.send(MeetingActivityContent(
                meeting: snapshot.meeting, phase: snapshot.phase, notchHeight: notchHeight,
                onJoin: { [weak self] in self?.join(snapshot.meeting, url: url) }))
        } else {
            subject.send(nil)
        }
        timer?.invalidate()
        let next = MeetingSchedule.nextChange(candidates: candidates, now: now, excluding: joinedIDs)
        let fire = min(next ?? .distantFuture, now.addingTimeInterval(3600))
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func join(_ meeting: MeetingCandidate, url: URL) {
        NSWorkspace.shared.open(url)
        joinedIDs.insert(meeting.id)
        refresh()
    }
}
