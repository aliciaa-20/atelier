import Foundation

/// Pure weather value types + Open-Meteo decoding. Foundation only, like
/// `CalendarMath` -- everything that touches CoreLocation or the network
/// lives in `WeatherSource`, so this file is unit-testable.

enum TemperatureUnit: String, Codable, Equatable {
    case celsius
    case fahrenheit

    /// Open-Meteo's `temperature_unit` query value.
    var queryValue: String { rawValue }

    static func forLocale(_ locale: Locale = .current) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

/// A WMO weather code boiled down to what the notch shows: an SF Symbol, a
/// spoken description (VoiceOver), and a one-liner for the Home row.
struct WeatherCondition: Equatable {
    let symbol: String
    let label: String
    let quip: String

    /// WMO codes as documented by Open-Meteo. Unknown codes fall back to a
    /// neutral cloud rather than hiding the row.
    static func from(code: Int) -> WeatherCondition {
        switch code {
        case 0:
            return .init(symbol: "sun.max.fill", label: "Clear", quip: "Suspiciously nice out")
        case 1, 2:
            return .init(symbol: "cloud.sun.fill", label: "Partly cloudy", quip: "A few clouds, no drama")
        case 3:
            return .init(symbol: "cloud.fill", label: "Overcast", quip: "The sky is a lid today")
        case 45, 48:
            return .init(symbol: "cloud.fog.fill", label: "Foggy", quip: "Very mysterious out there")
        case 51, 53, 55, 56, 57:
            return .init(symbol: "cloud.drizzle.fill", label: "Drizzle", quip: "Barely raining, technically")
        case 61, 63, 65, 66, 67:
            return .init(symbol: "cloud.rain.fill", label: "Rain", quip: "Umbrella weather")
        case 71, 73, 75, 77:
            return .init(symbol: "cloud.snow.fill", label: "Snow", quip: "Snow day energy")
        case 80, 81, 82:
            return .init(symbol: "cloud.heavyrain.fill", label: "Showers", quip: "Sudden rain, no warning")
        case 85, 86:
            return .init(symbol: "cloud.snow.fill", label: "Snow showers", quip: "Snow day energy")
        case 95, 96, 99:
            return .init(symbol: "cloud.bolt.rain.fill", label: "Thunderstorm", quip: "The sky is being dramatic")
        default:
            return .init(symbol: "cloud.fill", label: "Cloudy", quip: "Weather is happening")
        }
    }
}

struct DayWeather: Codable, Equatable {
    /// Local date at the forecast location, `yyyy-MM-dd`.
    let dayKey: String
    let code: Int
    let high: Double
    let low: Double

    var condition: WeatherCondition { .from(code: code) }
}

struct WeatherSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let unit: TemperatureUnit
    let currentTemp: Double
    let currentCode: Int
    let days: [DayWeather]

    var currentCondition: WeatherCondition { .from(code: currentCode) }

    func day(for date: Date, calendar: Calendar = .current) -> DayWeather? {
        let key = WeatherMath.dayKey(for: date, calendar: calendar)
        return days.first { $0.dayKey == key }
    }
}

enum WeatherMath {
    /// How long a fetched snapshot stays fresh -- the notch never polls.
    static let ttl: TimeInterval = 30 * 60

    static func isStale(fetchedAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) >= ttl
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Two decimals (~1 km) is plenty for a forecast and keeps precise
    /// position off the wire.
    static func roundedCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func requestURL(latitude: Double, longitude: Double, unit: TemperatureUnit) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            .init(name: "latitude", value: String(roundedCoordinate(latitude))),
            .init(name: "longitude", value: String(roundedCoordinate(longitude))),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: unit.queryValue),
            .init(name: "timezone", value: "auto"),
            .init(name: "past_days", value: "6"),
            .init(name: "forecast_days", value: "8"),
        ]
        return c?.url
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
        }
        let current: Current
        let daily: Daily
    }

    /// Days with any missing field are dropped instead of failing the decode.
    static func decode(_ data: Data, fetchedAt: Date, unit: TemperatureUnit) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(Response.self, from: data)
        let d = r.daily
        let days: [DayWeather] = d.time.enumerated().compactMap { i, key in
            guard i < d.weather_code.count, i < d.temperature_2m_max.count, i < d.temperature_2m_min.count,
                  let code = d.weather_code[i],
                  let hi = d.temperature_2m_max[i],
                  let lo = d.temperature_2m_min[i] else { return nil }
            return DayWeather(dayKey: key, code: code, high: hi, low: lo)
        }
        return WeatherSnapshot(fetchedAt: fetchedAt, unit: unit,
                               currentTemp: r.current.temperature_2m,
                               currentCode: r.current.weather_code, days: days)
    }
}
