import SwiftUI

/// Idle Home's weather detail card: shown in place of the clock when the
/// weather glance is tapped, and tap anywhere on it to go back. Current
/// conditions + today's high/low, the quip (which the glance only shows as a
/// tooltip), and the next five days. Sized by
/// `NotchLayout.idleWeatherDetailContentHeight`.
struct WeatherDetailView: View {
    let snapshot: WeatherSnapshot
    let onClose: () -> Void

    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private var condition: WeatherCondition { snapshot.currentCondition }
    private var today: DayWeather? { snapshot.day(for: .now) }

    /// The five days after today that the forecast covers.
    private var upcoming: [DayWeather] {
        let todayKey = WeatherMath.dayKey(for: .now)
        return Array(snapshot.days.filter { $0.dayKey > todayKey }.prefix(5))
    }

    private func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    var body: some View {
        Button(action: onClose) {
            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: condition.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                    Text(degrees(snapshot.currentTemp))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(condition.label)
                            .font(.caption.weight(.semibold))
                        if let today {
                            HStack(spacing: 5) {
                                Text("H \(degrees(today.high))")
                                Text("|").foregroundStyle(.white.opacity(0.25))
                                Text("L \(degrees(today.low))")
                            }
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                        }
                    }
                }

                Text(condition.quip)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !upcoming.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.top, 1)
                    HStack(spacing: 0) {
                        ForEach(upcoming, id: \.dayKey) { day in
                            VStack(spacing: 2) {
                                Text(weekday(day))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                                Image(systemName: day.condition.symbol)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 12))
                                    // Fixed height so every temp sits on one
                                    // baseline (glyphs differ in height).
                                    .frame(height: 16)
                                Text(degrees(day.high))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(weekday(day)), \(day.condition.label), high \(degrees(day.high))")
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel("Weather, \(condition.label), \(degrees(snapshot.currentTemp)). \(condition.quip)")
        .accessibilityHint("Double-tap to go back to the clock")
    }

    private func weekday(_ day: DayWeather) -> String {
        guard let date = Self.parseFormatter.date(from: day.dayKey) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }
}

/// Gentle press feedback for larger tap targets, where `ExpandedPlayerView`'s
/// transport-button style (scale to 0.88) would look heavy.
struct SoftPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
