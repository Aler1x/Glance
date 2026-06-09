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
    var forecast: [ForecastDay] = []
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
        static let forecast = "cache.forecast"
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
        if let data = defaults.data(forKey: Cache.forecast),
           let decoded = try? JSONDecoder().decode([ForecastDay].self, from: data) {
            forecast = decoded
        }
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
        // Keep the last good forecast if this fetch came back empty (transient failure).
        if !result.daily.isEmpty {
            forecast = result.daily
            if let data = try? JSONEncoder().encode(result.daily) {
                defaults.set(data, forKey: Cache.forecast)
            }
        }
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

// MARK: - Interactive frame preference

/// Collects the frames of every click-through-exempt control (quote button,
/// panel switcher) so the hosting view knows where to accept mouse events.
private struct InteractiveFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - View

struct DesktopWidgetView: View {
    @Bindable var model: WidgetModel
    var onInteractiveFramesChange: (([CGRect]) -> Void)?

    /// 0 = calendar, 1 = forecast.
    @State private var page = 0
    @State private var dragOffset: CGFloat = 0

    private static let pageCount = 2
    private static let pageSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    private let settings = WidgetSettings.shared

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                leftPanel
                rightPager
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: 530, height: 230)
        .overlay {
            if model.isEditing {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .coordinateSpace(name: "overlay")
        .colorScheme(.dark)
        .onAppear { model.start() }
        .onPreferenceChange(InteractiveFramesKey.self) { onInteractiveFramesChange?($0) }
    }

    // MARK: - Right pager (swipe between forecast / calendar)

    private var rightPager: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let headerHeight: CGFloat = 24
            let contentGap: CGFloat = 10
            let contentHeight = max(0, geo.size.height - headerHeight - contentGap)

            VStack(spacing: contentGap) {
                pagerTabs
                    .frame(height: headerHeight)

                HStack(spacing: 0) {
                    calendarPanel.frame(width: w)
                    forecastPanel.frame(width: w)
                }
                .frame(width: w, height: contentHeight, alignment: .leading)
                .offset(x: -CGFloat(page) * w + dragOffset)
                .clipped()
            }
            .frame(width: w, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(swipeGesture(width: w))
            .background(frameReporter)
        }
    }

    private var pagerTabs: some View {
        HStack(spacing: 8) {
            pagerTab(isSelected: page == 0) {
                Text(yearString)
            } action: {
                goTo(0)
            }

            pagerTab(isSelected: page == 1) {
                HStack(spacing: 5) {
                    Image(systemName: model.weatherSymbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(settings.weatherCity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            } action: {
                goTo(1)
            }
        }
        .frame(maxWidth: .infinity)
        .background(frameReporter)
    }

    private func pagerTab<Label: View>(
        isSelected: Bool,
        @ViewBuilder label: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.62)))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? .white.opacity(0.14) : .white.opacity(0.05))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !model.isEditing else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !model.isEditing else { return }
                let threshold = width / 4
                var target = page
                if value.translation.width < -threshold { target += 1 }
                else if value.translation.width > threshold { target -= 1 }
                goTo(target)
            }
    }

    private func goTo(_ index: Int) {
        let clamped = min(max(index, 0), Self.pageCount - 1)
        withAnimation(Self.pageSpring) {
            page = clamped
            dragOffset = 0
        }
    }

    /// Reports the frame of the view it backs into `InteractiveFramesKey`.
    private var frameReporter: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: InteractiveFramesKey.self,
                value: [geo.frame(in: .named("overlay"))]
            )
        }
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

            switch settings.panelContent {
            case .quote:
                if !model.quote.isEmpty {
                    quoteButton
                }
            case .equalizer:
                EqualizerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 12)
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
        .background(frameReporter)
    }

    private var timeRow: some View {
        ViewThatFits(in: .horizontal) {
            clockRow(spacing: 10, labelSize: 10, valueSize: 14)
            clockRow(spacing: 8, labelSize: 9, valueSize: 13)
            clockRow(spacing: 6, labelSize: 8, valueSize: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clockRow(spacing: CGFloat, labelSize: CGFloat, valueSize: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(settings.clocks.filter(\.enabled)) { clock in
                timeChip(clock.label, time(in: clock.timeZone), labelSize: labelSize, valueSize: valueSize)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func timeChip(_ label: String, _ value: String, labelSize: CGFloat, valueSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: valueSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Forecast / calendar panels

    private var forecastPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.forecast) { day in
                forecastRow(day)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }

    private func forecastRow(_ day: ForecastDay) -> some View {
        HStack(spacing: 10) {
            Text(day.weekdayLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            Image(systemName: day.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            Spacer(minLength: 0)

            Text(day.high)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(day.low)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 26)
    }

    private var calendarPanel: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.58))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 1)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
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
                                Circle()
                                    .fill(.white.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                                    }
                            }
                            Text("\(day)")
                                .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isToday ? .primary : .secondary)
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
