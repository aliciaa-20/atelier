import Foundation
import Testing
@testable import Atelier

struct WeatherModelTests {
    private let sample = """
    {"current":{"temperature_2m":18.2,"weather_code":3},
     "daily":{"time":["2026-09-23","2026-09-24","2026-09-25"],
              "weather_code":[61,0,null],
              "temperature_2m_max":[20.1,24.0,22.0],
              "temperature_2m_min":[12.0,13.5,11.0]}}
    """.data(using: .utf8)!

    @Test func decodesCurrentAndDropsIncompleteDays() throws {
        let s = try WeatherMath.decode(sample, fetchedAt: .now, unit: .celsius)
        #expect(s.currentTemp == 18.2)
        #expect(s.currentCode == 3)
        #expect(s.days.map(\.dayKey) == ["2026-09-23", "2026-09-24"])
        #expect(s.days[1].high == 24.0)
    }

    @Test func lookupByDate() throws {
        let s = try WeatherMath.decode(sample, fetchedAt: .now, unit: .celsius)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        #expect(s.day(for: d, calendar: cal)?.code == 0)
    }

    @Test func staleness() {
        let now = Date()
        #expect(!WeatherMath.isStale(fetchedAt: now.addingTimeInterval(-29 * 60), now: now))
        #expect(WeatherMath.isStale(fetchedAt: now.addingTimeInterval(-30 * 60), now: now))
    }

    @Test func requestURLRoundsCoordinates() {
        let url = WeatherMath.requestURL(latitude: 12.345678, longitude: -98.765432, unit: .fahrenheit)?.absoluteString ?? ""
        #expect(url.contains("latitude=12.35"))
        #expect(url.contains("longitude=-98.77"))
        #expect(url.contains("temperature_unit=fahrenheit"))
    }

    @Test func conditionMapping() {
        #expect(WeatherCondition.from(code: 0).symbol == "sun.max.fill")
        #expect(WeatherCondition.from(code: 65).label == "Rain")
        #expect(WeatherCondition.from(code: 999).symbol == "cloud.fill")
    }
}
