import AppKit
import SwiftUI

/// Calendar tab: a header (month + week chevrons), a 7-day strip with
/// event dots, and the selected day's agenda underneath. Sized by
/// `NotchController.calendarContentHeight` -- if you add rows here, check
/// that constant still fits.
struct CalendarPageView: View {
    @ObservedObject var source: CalendarSource

    private var calendar: Calendar { .current }

    var body: some View {
        Group {
            switch source.access {
            case .granted:
                VStack(spacing: 6) {
                    header
                    quip
                    weekStrip
                    agenda
                }
            case .notDetermined:
                message("Requesting calendar access…", actionTitle: nil, action: {})
            case .denied:
                message("Calendar access is off", actionTitle: "Open Settings") {
                    CalendarPermission.openSystemSettings()
                    source.recheckAccess()
                }
            }
        }
        .padding(.horizontal, NotchLayout.pageHorizontalInset)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            source.resetToToday()
            source.activate()
        }
    }

    // MARK: - Quip

    /// Session salt so the line differs between launches, while staying
    /// stable across re-renders for a given date.
    private static let sessionSalt = Int.random(in: 0..<1000)

    private var quip: some View {
        let seed = (calendar.ordinality(of: .day, in: .era, for: source.selectedDay) ?? 0) &+ Self.sessionSalt
        return Text(WeekdayQuips.quip(forWeekday: calendar.component(.weekday, from: source.selectedDay), seed: seed))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Text(source.weekStart, format: .dateTime.month(.wide).year())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            calendarFilter
            chevron("chevron.left", label: "Previous week") { source.shiftWeek(by: -1) }
            chevron("chevron.right", label: "Next week") { source.shiftWeek(by: 1) }
        }
    }

    /// Which calendars feed the tab. EventKit can't read Calendar.app's own
    /// sidebar checkboxes, so this is Atelier's own (persisted) filter.
    private var calendarFilter: some View {
        Menu {
            ForEach(source.calendars) { cal in
                Toggle(cal.title, isOn: Binding(
                    get: { cal.isEnabled },
                    set: { source.setCalendar(cal.id, enabled: $0) }
                ))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .fixedSize()
        .accessibilityLabel("Choose calendars")
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(label)
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(CalendarMath.days(inWeekStarting: source.weekStart, calendar: calendar), id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: source.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = !source.events(on: day).isEmpty
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                source.selectDay(day)
            }
        } label: {
            VStack(spacing: 2) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(day, format: .dateTime.day())
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.black : (isToday ? Color.red : Color.white))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isSelected ? Color.white : Color.clear))
                Circle()
                    .fill(Color.white.opacity(hasEvents ? 0.7 : 0))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()) + (hasEvents ? ", has events" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Agenda

    private var agenda: some View {
        let items = source.events(on: source.selectedDay)
        return Group {
            if items.isEmpty {
                Button { openCalendar() } label: {
                    Text("No events · open Calendar to add one")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: NotchLayout.calendarRowSpacing) {
                        ForEach(items) { item in
                            Button { openCalendar() } label: { agendaRow(item) }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                        }
                    }
                }
            }
        }
    }

    private func agendaRow(_ item: CalendarEventItem) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(item.color.map { Color(cgColor: $0) } ?? Color.white.opacity(0.5))
                .frame(width: 3, height: NotchLayout.calendarRowHeight - 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeText(for: item))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Opens Calendar.app on the selected day -- adding/editing happens
    /// there, so the notch never needs write access or text input.
    private func openCalendar() {
        let seconds = source.selectedDay.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(seconds)") { NSWorkspace.shared.open(url) }
    }

    private func timeText(for item: CalendarEventItem) -> String {
        if item.isAllDay { return "All day" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        return "\(item.start.formatted(time)) – \(item.end.formatted(time))"
    }

    // MARK: - Non-granted states

    private func message(_ text: String, actionTitle: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
