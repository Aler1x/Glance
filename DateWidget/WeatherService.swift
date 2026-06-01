//
//  WeatherService.swift
//  WeatherService
//
//  Created by Alerix and Claude on 1.06.2026.
//

import CoreLocation
import Foundation
internal import Combine

final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: String = "–°C"
    @Published var symbolName: String = "cloud"

    // nonisolated(unsafe): CLLocationManager must be used on main thread;
    // all access here is on the main actor (project default).
    nonisolated(unsafe) private let manager = CLLocationManager()
    private var refreshTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorized ||
              manager.authorizationStatus == .authorizedAlways else { return }
        Task { @MainActor in
            self.manager.requestLocation()
            self.scheduleRefresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        Task { @MainActor in
            await self.fetchWeather(lat: lat, lon: lon)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Weather fetch

    private func fetchWeather(lat: Double, lon: Double) async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weathercode&temperature_unit=celsius"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double,
              let code = current["weathercode"] as? Int else { return }

        temperature = "\(Int(temp.rounded()))°C"
        symbolName = symbol(for: code)
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.manager.requestLocation()
        }
    }

    // MARK: - WMO code → SF Symbol

    private func symbol(for code: Int) -> String {
        switch code {
        case 0:       return "sun.max"
        case 1, 2:    return "cloud.sun"
        case 3:       return "cloud"
        case 45, 48:  return "cloud.fog"
        case 51...67: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.heavyrain"
        case 95...99: return "cloud.bolt"
        default:      return "cloud"
        }
    }
}
