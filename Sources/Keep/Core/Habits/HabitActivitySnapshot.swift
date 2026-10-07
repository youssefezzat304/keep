import Foundation

/// Prepares dates, counts and labels once per data/day change, independent of the display mode.
struct HabitActivitySnapshot {
    struct Day {
        let date: Date
        let count: Int
        let inYear: Bool
        let future: Bool
        let label: String
    }
    struct Week {
        let days: [Day]
        let total: Int
        let month: String
        let label: String
    }
    let year: Int
    let weeks: [Week]
    var total: Int { weeks.reduce(0) { $0 + $1.total } }

    init(archive: HabitArchive, today: Date, calendar: Calendar) {
        year = calendar.component(.year, from: today)
        let todayID = TaskDay.id(for: today, calendar: calendar)
        let goals = Dictionary(uniqueKeysWithValues: archive.habits.map { ($0.id, $0.goal.target) })
        var counts: [String: Int] = [:]
        for log in archive.logs where log.dayID <= todayID {
            if let target = goals[log.habitID], log.amount >= target { counts[log.dayID, default: 0] += 1 }
        }
        let currentYear = year
        weeks = HabitDates.yearWeeks(containing: today, calendar: calendar).map { dates in
            let days = dates.map { date in
                let id = TaskDay.id(for: date, calendar: calendar)
                let inYear = calendar.component(.year, from: date) == currentYear
                let count = inYear ? counts[id, default: 0] : 0
                let name = HabitDates.label(date, calendar: calendar, style: .dateTime.day().month(.wide).year())
                return Day(date: date, count: count, inYear: inYear, future: id > todayID, label: "\(name): \(count) habits completed")
            }
            let total = days.reduce(0) { $0 + $1.count }
            let month = dates.first { calendar.component(.year, from: $0) == currentYear && calendar.component(.day, from: $0) == 1 }
                .map { HabitDates.label($0, calendar: calendar, style: .dateTime.month(.abbreviated)) } ?? " "
            let weekName = dates.first.map { HabitDates.label($0, calendar: calendar, style: .dateTime.day().month(.wide)) } ?? ""
            return Week(days: days, total: total, month: month, label: "Week of \(weekName): \(total) habits completed")
        }
    }
}
