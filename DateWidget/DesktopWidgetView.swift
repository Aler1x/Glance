//
//  DesktopWidgetView.swift
//  DateWidget
//
//  Created by Alerix and Claude on 01.06.2026.
//

import AppKit
import Observation
import SwiftUI

// MARK: - Model

@MainActor
@Observable
final class WidgetModel {
    var now = Date()
    var quote = ""
    var temperature = "–°C"
    var weatherSymbol = "cloud"
    var isEditing = false
    private(set) var isRefreshing = false

    private let settings = WidgetSettings.shared
    private let defaults = UserDefaults.standard

    private var minuteTimer: Timer?
    private var weatherTimer: Timer?
    private var quoteTimer: Timer?
    private var started = false

    private static let refreshInterval: TimeInterval = 3600

    private enum Cache {
        static let quote = "cache.quote"
        static let quoteDate = "cache.quoteDate"
        static let temperature = "cache.temperature"
        static let symbol = "cache.weatherSymbol"
        static let weatherDate = "cache.weatherDate"
    }

    func start() {
        guard !started else { return }
        started = true

        loadCache()
        scheduleMinuteTick()
        scheduleWeatherRefresh()
        scheduleQuoteRefresh()
        observeSystemEvents()
        observeWeatherSettings()

        Task {
            await refreshWeather()
            await refresh()
        }
    }

    /// Fetches a new quote — from the hourly timer, a wake, or a manual request
    /// (tapping the quote / the Refresh Quote menu item).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let fetched = await QuoteService.fetch()
        if !fetched.isEmpty {
            quote = fetched
            cacheQuote()
        }
        isRefreshing = false
    }

    // MARK: Cache

    private func loadCache() {
        if let cached = defaults.string(forKey: Cache.quote), !cached.isEmpty { quote = cached }
        if let temp = defaults.string(forKey: Cache.temperature) { temperature = temp }
        if let symbol = defaults.string(forKey: Cache.symbol) { weatherSymbol = symbol }
    }

    private func cacheQuote() {
        defaults.set(quote, forKey: Cache.quote)
        defaults.set(Date(), forKey: Cache.quoteDate)
    }

    private func isFresh(_ key: String) -> Bool {
        guard let last = defaults.object(forKey: key) as? Date else { return false }
        return Date().timeIntervalSince(last) < Self.refreshInterval
    }

    // MARK: Clock

    private func scheduleMinuteTick() {
        minuteTimer?.invalidate()
        now = Date()
        let next = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    // MARK: Weather

    private func scheduleWeatherRefresh() {
        weatherTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshWeather() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        weatherTimer = timer
    }

    private func refreshWeather() async {
        let result = await WeatherService.fetch(
            latitude: settings.latitude,
            longitude: settings.longitude,
            fahrenheit: settings.useFahrenheit
        )
        temperature = result.temperature
        weatherSymbol = result.symbolName
        defaults.set(result.temperature, forKey: Cache.temperature)
        defaults.set(result.symbolName, forKey: Cache.symbol)
        defaults.set(Date(), forKey: Cache.weatherDate)
    }

    // MARK: Quote

    private func scheduleQuoteRefresh() {
        quoteTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        quoteTimer = timer
    }

    // MARK: System events

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleWake()
            }
        }

        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor [weak self] in self?.scheduleMinuteTick() }
            }
        }
    }

    private func handleWake() async {
        scheduleMinuteTick()
        if !isFresh(Cache.weatherDate) { await refreshWeather() }
        if !isFresh(Cache.quoteDate) { await refresh() }
    }

    // MARK: Settings observation

    private func observeWeatherSettings() {
        withObservationTracking {
            _ = settings.latitude
            _ = settings.longitude
            _ = settings.useFahrenheit
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshWeather()
                self.observeWeatherSettings()
            }
        }
    }
}

// MARK: - Button frame preference

private struct ButtonFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - View

struct DesktopWidgetView: View {
    @Bindable var model: WidgetModel
    var onButtonFrameChange: ((CGRect) -> Void)?

    private let settings = WidgetSettings.shared

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                leftPanel
                rightPanel
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: 520, height: 230)
        .overlay {
            if model.isEditing {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .coordinateSpace(name: "overlay")
        .colorScheme(.dark)
        .onAppear { model.start() }
        .onPreferenceChange(ButtonFrameKey.self) { onButtonFrameChange?($0) }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            timeRow

            Spacer().frame(height: 10)

            HStack(alignment: .center, spacing: 10) {
                Text(dayString)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: model.weatherSymbol)
                            .font(.system(size: 13))
                        Text(model.temperature)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    Text(monthWeekdayString)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
            }

            if !model.quote.isEmpty {
                quoteButton
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 16)
    }

    private var quoteButton: some View {
        Button { Task { await model.refresh() } } label: {
            Text(model.quote)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ButtonFrameKey.self,
                    value: geo.frame(in: .named("overlay"))
                )
            }
        )
    }

    private var timeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            ForEach(settings.clocks.filter(\.enabled)) { clock in
                timeChip(clock.label, time(in: clock.timeZone))
            }
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func timeChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(value)
        }
    }

    // MARK: - Right panel (calendar)

    private var rightPanel: some View {
        VStack(spacing: 5) {
            Text(yearString)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                spacing: 2
            ) {
                ForEach(0..<calendarDays.count, id: \.self) { idx in
                    let day = calendarDays[idx]
                    if day == 0 {
                        Color.clear.frame(height: 26)
                    } else {
                        let isToday = day == currentDayNumber
                        ZStack {
                            if isToday {
                                Circle().fill(.tertiary).frame(width: 26, height: 26)
                            }
                            Text("\(day)")
                                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 4)
    }

    // MARK: - Helpers

    private func time(in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = zone
        return f.string(from: model.now)
    }

    private var dayString: String { "\(Calendar.current.component(.day, from: model.now))" }

    private var monthWeekdayString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM, EEE"
        return f.string(from: model.now)
    }

    private var yearString: String { "\(Calendar.current.component(.year, from: model.now))" }
    private var currentDayNumber: Int { Calendar.current.component(.day, from: model.now) }

    private var calendarDays: [Int] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.year, .month], from: model.now)
        guard let firstDay = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: model.now)
        else { return [] }
        let weekday = cal.component(.weekday, from: firstDay)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        return Array(repeating: 0, count: offset) + Array(1...range.count)
    }
}
