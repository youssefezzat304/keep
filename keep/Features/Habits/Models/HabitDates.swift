import Foundation

enum HabitDates {
    static func label(_ date: Date, calendar: Calendar, style: Date.FormatStyle) -> String {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .current
        return date.formatted(style)
    }
    static func weekdayLabels(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols.dropFirst()) + [symbols[0]]
    }

    static func weekDays(containing date: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: start) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
    static func monthDays(containing date: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date), let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return (0..<days.count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
    static func monthGrid(containing date: Date, calendar: Calendar) -> [Date] {
        guard let first = monthDays(containing: date, calendar: calendar).first else { return [] }
        let start = weekDays(containing: first, calendar: calendar).first ?? first
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    static func yearWeeks(containing date: Date, calendar: Calendar) -> [[Date]] {
        guard let year = calendar.dateInterval(of: .year, for: date),
              let start = weekDays(containing: year.start, calendar: calendar).first else { return [] }
        var weeks: [[Date]] = []
        var cursor = start
        while cursor < year.end {
            weeks.append(weekDays(containing: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// A square means one completed goal, with seven or more filling the column.
    static func weeklyHeight(completions: Int) -> Int { min(7, max(0, completions)) }
}
