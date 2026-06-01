//
//  DateWidget.swift
//  DateWidget
//
//  Created by Alerix on 01.06.2026.
//

import SwiftUI
import WidgetKit

// MARK: - Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let quote: String
    let temperature: String
    let weatherSymbol: String
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), quote: "", temperature: "–°C", weatherSymbol: "cloud")
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        Task {
            async let quote = QuoteService.fetch()
            async let weather = WeatherService.fetch()
            let (q, w) = await (quote, weather)
            let entry = WidgetEntry(
                date: Date(),
                quote: q,
                temperature: w.temperature,
                weatherSymbol: w.symbolName
            )
            let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

// MARK: - View

struct DateWidgetEntryView: View {
    var entry: WidgetEntry

    private let newYork = TimeZone(identifier: "America/New_York") ?? .current

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftPanel
            rightPanel
        }
        .colorScheme(.dark)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.18),
                    Color(red: 0.04, green: 0.04, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            timeRow

            Spacer().frame(height: 6)

            HStack(alignment: .center, spacing: 6) {
                Text(dayString)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.weatherSymbol)
                            .font(.system(size: 12))
                        Text(entry.temperature)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    Text(monthWeekdayString)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if !entry.quote.isEmpty {
                Text(entry.quote)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        .tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("UA")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(time(in: .current))
            }
            HStack(spacing: 4) {
                Text("NY")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(time(in: newYork))
            }
            //            HStack(spacing: 4) {
            //                Text("WR")
            //                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            //                    .foregroundStyle(.tertiary)
            //                Text(time(in: warsaw))
            //            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }

    // MARK: - Right panel (calendar)

    private var rightPanel: some View {
        VStack(spacing: 4) {
            Text(yearString)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
                spacing: 1
            ) {
                ForEach(0..<calendarDays.count, id: \.self) { idx in
                    let day = calendarDays[idx]
                    if day == 0 {
                        Color.clear.frame(height: 22)
                    } else {
                        let isToday = day == currentDayNumber
                        ZStack {
                            if isToday {
                                Circle()
                                    .fill(.tertiary)
                                    .frame(width: 22, height: 22)
                            }
                            Text("\(day)")
                                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                                .foregroundStyle(AnyShapeStyle(.secondary))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func time(in zone: TimeZone) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = zone
        return f.string(from: entry.date)
    }

    private var dayString: String {
        "\(Calendar.current.component(.day, from: entry.date))"
    }

    private var monthWeekdayString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM, EEE"
        return f.string(from: entry.date)
    }

    private var yearString: String {
        "\(Calendar.current.component(.year, from: entry.date))"
    }

    private var currentDayNumber: Int {
        Calendar.current.component(.day, from: entry.date)
    }

    private var calendarDays: [Int] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.year, .month], from: entry.date)
        guard let firstDay = cal.date(from: comps),
            let range = cal.range(of: .day, in: .month, for: entry.date)
        else { return [] }

        let weekday = cal.component(.weekday, from: firstDay)
        let offset = (weekday - cal.firstWeekday + 7) % 7

        return Array(repeating: 0, count: offset) + Array(1...range.count)
    }
}

// MARK: - Widget

struct DateWidget: Widget {
    let kind: String = "DateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DateWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Date & Time")
        .description("Date, time, weather, and a daily quote.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
