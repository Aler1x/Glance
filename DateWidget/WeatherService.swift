//
//  WeatherService.swift
//  DateWidget
//
//  Created by Alerix and Claude on 1.06.2026.
//

import Foundation

/// A single day in the multi-day forecast strip.
struct ForecastDay: Codable, Identifiable {
    let date: String  // raw ISO local date, e.g. "2026-06-09"
    let high: String
    let low: String
    let symbolName: String

    var id: String { date }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// "2026-06-09" -> "Tue"
    var weekdayLabel: String {
        guard let parsed = Self.parser.date(from: date) else { return date }
        return Self.weekday.string(from: parsed)
    }
}

struct WeatherSnapshot {
    let temperature: String
    let symbolName: String
    let daily: [ForecastDay]
}

enum WeatherService {
    private static let forecastDays = 6

    // Kyiv, Ukraine — defaults
    static func fetch(
        latitude: Double = 50.45,
        longitude: Double = 30.52,
        fahrenheit: Bool = false
    ) async -> WeatherSnapshot {
        let unit = fahrenheit ? "fahrenheit" : "celsius"
        let degrees = fahrenheit ? "°F" : "°C"
        let urlString =
            "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weathercode&daily=weathercode,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=\(forecastDays)&temperature_unit=\(unit)"
        guard let url = URL(string: urlString),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = json["current"] as? [String: Any],
            let temp = current["temperature_2m"] as? Double,
            let code = current["weathercode"] as? Int
        else { return WeatherSnapshot(temperature: "–\(degrees)", symbolName: "cloud", daily: []) }

        return WeatherSnapshot(
            temperature: "\(Int(temp.rounded()))\(degrees)",
            symbolName: symbol(for: code),
            daily: dailyForecast(from: json, degrees: degrees)
        )
    }

    /// Builds the day-by-day forecast. The daily series already starts at today,
    /// so the entries are taken in order.
    private static func dailyForecast(
        from json: [String: Any],
        degrees: String
    ) -> [ForecastDay] {
        guard let daily = json["daily"] as? [String: Any],
            let dates = daily["time"] as? [String],
            let highs = daily["temperature_2m_max"] as? [Double],
            let lows = daily["temperature_2m_min"] as? [Double],
            let codes = daily["weathercode"] as? [Int]
        else { return [] }

        let count = min(dates.count, highs.count, lows.count, codes.count, forecastDays)
        return (0..<count).map { i in
            ForecastDay(
                date: dates[i],
                high: "\(Int(highs[i].rounded()))\(degrees)",
                low: "\(Int(lows[i].rounded()))\(degrees)",
                symbolName: symbol(for: codes[i])
            )
        }
    }

    /// Resolves a free-text place name to coordinates via the open-meteo geocoder.
    static func geocode(city: String) async -> (latitude: Double, longitude: Double, name: String)? {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string:
                    "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"
            ),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first = results.first,
            let lat = first["latitude"] as? Double,
            let lon = first["longitude"] as? Double,
            let name = first["name"] as? String
        else { return nil }

        let country = first["country"] as? String
        let display = country.map { "\(name), \($0)" } ?? name
        return (lat, lon, display)
    }

    private static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...67: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.heavyrain"
        case 95...99: return "cloud.bolt"
        default: return "cloud"
        }
    }
}
