//
//  DateWidgetView.swift
//  DateWidget
//
//  Created by Alerix and Claude on 26.05.2026.
//

import SwiftUI
internal import Combine

struct DateWidgetView: View {
    @State private var currentDate = Date()
    @StateObject private var weather = WeatherService()
    @StateObject private var quote = QuoteService()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let newYork = TimeZone(identifier: "America/New_York") ?? .current
    private let warsaw = TimeZone(identifier: "Europe/Warsaw") ?? .current

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
        .onReceive(timer) { currentDate = $0 }
        .frame(width: 520, height: 230)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            timeRow

            Spacer().frame(height: 10)

            HStack(alignment: .center, spacing: 10) {
                Text(dayString)
                    .font(.system(size: 70, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 100, alignment: .trailing)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: weather.symbolName)
                            .font(.system(size: 13))
                        Text(weather.temperature)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    Text(monthWeekdayString)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
            }

            if !quote.text.isEmpty {
                Text(quote.text)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 16)
    }

    private var timeRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("UA")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(time(in: .current))
            }
            HStack(spacing: 4) {
                Text("NY")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(time(in: newYork))
            }
            HStack(spacing: 4) {
                Text("WR")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(time(in: warsaw))
            }
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }

    // MARK: - Right panel

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
                                Circle()
                                    .fill(.tertiary)
                                    .frame(width: 26, height: 26)
                            }
                            Text("\(day)")
                                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                                .foregroundStyle(AnyShapeStyle(.secondary))
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
        return f.string(from: currentDate)
    }

    private var dayString: String {
        "\(Calendar.current.component(.day, from: currentDate))"
    }

    private var monthWeekdayString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM, EEE"
        return f.string(from: currentDate)
    }

    private var yearString: String {
        "\(Calendar.current.component(.year, from: currentDate))"
    }

    private var currentDayNumber: Int {
        Calendar.current.component(.day, from: currentDate)
    }

    private var calendarDays: [Int] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.year, .month], from: currentDate)
        guard let firstDay = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: currentDate) else { return [] }

        let weekday = cal.component(.weekday, from: firstDay)
        let offset = (weekday - cal.firstWeekday + 7) % 7

        return Array(repeating: 0, count: offset) + Array(1...range.count)
    }
}

#Preview {
    DateWidgetView()
        .padding(40)
}
