//
//  SettingsView.swift
//  DateWidget
//
//  Created by Alerix and Claude on 01.06.2026.
//

import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = WidgetSettings.shared

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var cityField = WidgetSettings.shared.weatherCity
    @State private var isLookingUp = false
    @State private var lookupError: String?

    private static let timeZoneIDs = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        Form {
            clocksSection
            weatherSection
            appearanceSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 560)
    }

    // MARK: Clocks

    private var clocksSection: some View {
        Section {
            ForEach($settings.clocks) { $clock in
                HStack(spacing: 12) {
                    Toggle("", isOn: $clock.enabled)
                        .labelsHidden()
                    TextField("Label", text: $clock.label)
                        .labelsHidden()
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                    Picker("", selection: $clock.timeZoneID) {
                        Text("Device Local").tag(String?.none)
                        ForEach(Self.timeZoneIDs, id: \.self) { id in
                            Text(id).tag(String?.some(id))
                        }
                    }
                    .labelsHidden()
                }
            }
        } header: {
            Label("Clocks", systemImage: "clock")
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        Section {
            HStack {
                TextField("City", text: $cityField)
                    .onSubmit { lookUpCity() }
                Button(action: lookUpCity) {
                    if isLookingUp { ProgressView().controlSize(.small) } else { Text("Look up") }
                }
                .disabled(isLookingUp)
            }
            LabeledContent("Coordinates") {
                Text(String(format: "%.3f, %.3f", settings.latitude, settings.longitude))
                    .foregroundStyle(.secondary)
            }
            if let lookupError {
                Text(lookupError).font(.caption).foregroundStyle(.red)
            }
            Picker("Units", selection: $settings.useFahrenheit) {
                Text("Celsius (°C)").tag(false)
                Text("Fahrenheit (°F)").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            Label("Weather", systemImage: "cloud.sun")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Left panel", selection: $settings.panelContent) {
                ForEach(PanelContent.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Contrast backing", isOn: $settings.contrastBacking)
            if settings.contrastBacking {
                HStack {
                    Text("Opacity")
                    Slider(value: $settings.backingOpacity, in: 0.1...1.0)
                }
            }
        } header: {
            Label("Appearance", systemImage: "paintbrush")
        }
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.set(newValue)
                    launchAtLogin = LoginItem.isEnabled
                }
        } header: {
            Label("General", systemImage: "gearshape")
        }
    }

    // MARK: Actions

    private func lookUpCity() {
        let query = cityField
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLookingUp = true
        lookupError = nil
        Task {
            if let result = await WeatherService.geocode(city: query) {
                settings.latitude = result.latitude
                settings.longitude = result.longitude
                settings.weatherCity = result.name
                cityField = result.name
            } else {
                lookupError = "Couldn't find “\(query)”."
            }
            isLookingUp = false
        }
    }
}
