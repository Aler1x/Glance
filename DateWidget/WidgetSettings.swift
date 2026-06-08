//
//  WidgetSettings.swift
//  DateWidget
//
//  Created by Alerix and Claude on 01.06.2026.
//

import Foundation
import ServiceManagement
import AppKit

// MARK: - Clock config

struct ClockConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var timeZoneID: String?  // nil = device local
    var enabled: Bool

    var timeZone: TimeZone {
        timeZoneID.flatMap { TimeZone(identifier: $0) } ?? .current
    }

    static let defaults: [ClockConfig] = [
        ClockConfig(label: "UA", timeZoneID: nil, enabled: true),
        ClockConfig(label: "NY", timeZoneID: "America/New_York", enabled: true),
        ClockConfig(label: "WR", timeZoneID: "Europe/Warsaw", enabled: true),
    ]
}

// MARK: - Login item

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("LoginItem update failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Settings store

@Observable
final class WidgetSettings {
    static let shared = WidgetSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let clocks = "settings.clocks"
        static let city = "settings.weatherCity"
        static let lat = "settings.latitude"
        static let lon = "settings.longitude"
        static let fahrenheit = "settings.useFahrenheit"
        static let contrast = "settings.contrastBacking"
        static let opacity = "settings.backingOpacity"
    }

    var clocks: [ClockConfig] { didSet { saveClocks() } }
    var weatherCity: String { didSet { defaults.set(weatherCity, forKey: Key.city) } }
    var latitude: Double { didSet { defaults.set(latitude, forKey: Key.lat) } }
    var longitude: Double { didSet { defaults.set(longitude, forKey: Key.lon) } }
    var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: Key.fahrenheit) } }
    var contrastBacking: Bool { didSet { defaults.set(contrastBacking, forKey: Key.contrast) } }
    var backingOpacity: Double { didSet { defaults.set(backingOpacity, forKey: Key.opacity) } }

    private init() {
        if let data = defaults.data(forKey: Key.clocks),
           let decoded = try? JSONDecoder().decode([ClockConfig].self, from: data) {
            clocks = decoded
        } else {
            clocks = ClockConfig.defaults
        }
        weatherCity = defaults.string(forKey: Key.city) ?? "Kyiv"
        latitude = defaults.object(forKey: Key.lat) as? Double ?? 50.45
        longitude = defaults.object(forKey: Key.lon) as? Double ?? 30.52
        useFahrenheit = defaults.bool(forKey: Key.fahrenheit)
        contrastBacking = defaults.bool(forKey: Key.contrast)
        backingOpacity = defaults.object(forKey: Key.opacity) as? Double ?? 0.5
    }

    private func saveClocks() {
        if let data = try? JSONEncoder().encode(clocks) {
            defaults.set(data, forKey: Key.clocks)
        }
    }
}
