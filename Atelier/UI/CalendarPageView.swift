import AppKit
import SwiftUI

/// Calendar tab: a header (month + week chevrons), a 7-day strip with
/// event dots, and the selected day's agenda underneath. Sized by
/// `NotchController.calendarContentHeight` -- if you add rows here, check
/// that constant still fits.
struct CalendarPageView: View {
    @ObservedObject var source: CalendarSource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .help("Choose calendars")
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
        .help(label)
    }

    // MARK: - Week strip

    private static let indicatorSize: CGFloat = 26
    /// How much wider than a circle the indicator gets at the midpoint
    /// between two days. Visual tuning constant.
    private static let indicatorStretch: CGFloat = 14
    /// Vertical offset of the date row inside a day cell (below the weekday
    /// letter). Visual tuning constant.
    private static let indicatorTopInset: CGFloat = 13

    /// Indicator offset toward the neighbouring day; 0 with Reduce Motion so
    /// it steps instead of gliding and stretching.
    private var indicatorFraction: CGFloat { reduceMotion ? 0 : source.scrubFraction }

    private var weekStrip: some View {
        let days = CalendarMath.days(inWeekStarting: source.weekStart, calendar: calendar)
        let selectedIndex = days.firstIndex { calendar.isDate($0, inSameDayAs: source.selectedDay) }
        // `.id(weekStart)` + a transition: when the swipe rolls into another
        // week the whole strip (dates and indicator) swaps as one instead of
        // the dates snapping and the indicator flying across six columns.
        return ZStack {
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    dayCell(day, underIndicator: isUnderIndicator(index, selectedIndex: selectedIndex))
                }
            }
            .background(alignment: .topLeading) { indicator(selectedIndex: selectedIndex) }
            .id(source.weekStart)
            // The incoming week slides in from the side of travel; the
            // outgoing one just fades (an outgoing view keeps the transition
            // it was rendered with, so a direction-based removal would point
            // the wrong way after a reversal).
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: source.weekDirection * 28)),
                removal: .opacity
            ))
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: source.weekStart)
    }

    /// While the finger is down: a light interactive spring, so the capsule
    /// eases toward the finger instead of snapping 1:1 (graceful, not jittery).
    /// After release and on taps: a softer spring settle.
    private var indicatorAnimation: Animation? {
        if reduceMotion { return nil }
        return source.isScrubbing
            ? .interactiveSpring(response: 0.22, dampingFraction: 0.9)
            : .spring(response: 0.35, dampingFraction: 0.8)
    }

    /// A day's label turns black while the white indicator covers it: the
    /// selected day, plus the neighbour it is stretching toward.
    private func isUnderIndicator(_ index: Int, selectedIndex: Int?) -> Bool {
        guard let selectedIndex else { return false }
        if index == selectedIndex { return true }
        let f = indicatorFraction
        return abs(f) > 0.3 && index == selectedIndex + (f > 0 ? 1 : -1)
    }

    /// One white capsule behind the strip instead of a circle per cell, so
    /// it can slide and stretch between days like the tab bar's dot.
    private func indicator(selectedIndex: Int?) -> some View {
        GeometryReader { geo in
            if let selectedIndex {
                let columnWidth = geo.size.width / 7
                let f = indicatorFraction
                Capsule()
                    .fill(Color.white)
                    .frame(width: Self.indicatorSize + Self.indicatorStretch * abs(f) * 2, height: Self.indicatorSize)
                    .position(
                        x: (CGFloat(selectedIndex) + 0.5 + f) * columnWidth,
                        y: Self.indicatorTopInset + Self.indicatorSize / 2
                    )
                    .animation(indicatorAnimation, value: f)
                    .animation(indicatorAnimation, value: selectedIndex)
            }
        }
        .allowsHitTesting(false)
    }

    private func dayCell(_ day: Date, underIndicator: Bool) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: source.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = !source.events(on: day).isEmpty
        return Button {
            withAnimation(NotchAnimations.standard) {
                source.selectDay(day)
            }
        } label: {
            VStack(spacing: 2) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(day, format: .dateTime.day())
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(underIndicator ? Color.black : (isToday ? Color.red : Color.white))
                    .frame(width: Self.indicatorSize, height: Self.indicatorSize)
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
        // `simultaneousGesture`, not a second `onTapGesture`: a single tap
        // must still select instantly rather than wait out the double-tap
        // timeout. The Button above keeps VoiceOver's tap-to-select intact.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                source.selectDay(day)
                openCalendar(on: day)
            }
        )
        .accessibilityAction(named: "Open in calendar app") {
            source.selectDay(day)
            openCalendar(on: day)
        }
    }

    // MARK: - Agenda

    private var agenda: some View {
        let items = source.events(on: source.selectedDay)
        return Group {
            if items.isEmpty {
                Button { openCalendar() } label: {
                    Text("Nothing planned · tap to add something")
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

    /// Opens the user's chosen calendar app (menu bar setting) -- adding and
    /// editing happens there, so the notch never needs write access or text
    /// input. Calendar.app jumps to the selected day; other apps just launch.
    private func openCalendar(on day: Date? = nil) {
        CalendarAppLauncher.open(on: day ?? source.selectedDay)
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
