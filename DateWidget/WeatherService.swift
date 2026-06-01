//
//  WeatherService.swift
//  DateWidget
//
//  Created by Alerix and Claude on 1.06.2026.
//

import Foundation

enum WeatherService {
    // Kyiv, Ukraine
    private static let lat = 50.45
    private static let lon = 30.52

    static func fetch() async -> (temperature: String, symbolName: String) {
        let urlString =
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weathercode&temperature_unit=celsius"
        guard let url = URL(string: urlString),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = json["current"] as? [String: Any],
            let temp = current["temperature_2m"] as? Double,
            let code = current["weathercode"] as? Int
        else { return ("–°C", "cloud") }

        return ("\(Int(temp.rounded()))°C", symbol(for: code))
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
