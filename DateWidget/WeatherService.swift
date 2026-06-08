//
//  WeatherService.swift
//  DateWidget
//
//  Created by Alerix and Claude on 1.06.2026.
//

import Foundation

enum WeatherService {
    // Kyiv, Ukraine — defaults
    static func fetch(
        latitude: Double = 50.45,
        longitude: Double = 30.52,
        fahrenheit: Bool = false
    ) async -> (temperature: String, symbolName: String) {
        let unit = fahrenheit ? "fahrenheit" : "celsius"
        let degrees = fahrenheit ? "°F" : "°C"
        let urlString =
            "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weathercode&temperature_unit=\(unit)"
        guard let url = URL(string: urlString),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = json["current"] as? [String: Any],
            let temp = current["temperature_2m"] as? Double,
            let code = current["weathercode"] as? Int
        else { return ("–\(degrees)", "cloud") }

        return ("\(Int(temp.rounded()))\(degrees)", symbol(for: code))
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
