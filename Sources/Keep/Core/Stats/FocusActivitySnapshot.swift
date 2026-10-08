import Foundation

/// A year of civil days, with only the selected date range contributing recorded hours.
nonisolated struct FocusActivitySnapshot: Sendable {
    struct Day: Sendable {
        let id: String
        let date: Date
        let inYear: Bool
        let selected: Bool
        let future: Bool
        let label: String
        var seconds: Double = 0
    }
    struct Week: Sendable {
        var days: [Day]
        let month: String
        var seconds: Double { days.reduce(0) { $0 + $1.seconds } }
    }
    let year: Int
    var weeks: [Week]
    var seconds: Double { weeks.reduce(0) { $0 + $1.seconds } }

    init(range: StatsRange, now: Date, calendar: Calendar) {
        year = calendar.component(.year, from: range.start)
        weeks = []
        guard let interval = calendar.dateInterval(of: .year, for: range.start) else { return }
        let offset = (calendar.component(.weekday, from: interval.start) + 5) % 7
        guard var cursor = calendar.date(byAdding: .day, value: -offset, to: interval.start) else { return }
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = calendar.locale
        formatter.dateFormat = "d MMM yyyy"
        while cursor < interval.end {
            var days: [Day] = []
            for index in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: index, to: cursor) else { continue }
                days.append(Day(id: StatsSnapshot.dayID(date, calendar: calendar), date: date,
                    inYear: date >= interval.start && date < interval.end,
                    selected: date >= range.start && date < range.end, future: date > today, label: formatter.string(from: date)))
            }
            let firstOfMonth = days.first { $0.inYear && calendar.component(.day, from: $0.date) == 1 }
            let month = firstOfMonth.map { calendar.shortMonthSymbols[calendar.component(.month, from: $0.date) - 1] } ?? " "
            weeks.append(Week(days: days, month: month))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor), next > cursor else { break }
            cursor = next
        }
    }

    func filling(_ daily: [String: Double]) -> Self {
        var value = self
        for week in value.weeks.indices {
            for day in value.weeks[week].days.indices {
                let tile = value.weeks[week].days[day]
                value.weeks[week].days[day].seconds = tile.inYear && tile.selected && !tile.future ? max(0, daily[tile.id, default: 0]) : 0
            }
        }
        return value
    }

    static func intensity(seconds: Double) -> Int {
        guard seconds > 0 else { return 0 }
        let hours = seconds / 3600
        return hours < 2 ? 1 : hours < 4 ? 2 : hours < 8 ? 3 : 4
    }
}
