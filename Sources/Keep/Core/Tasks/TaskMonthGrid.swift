import Foundation

/// Calendar arithmetic keeps the grid aligned with local weekdays, leap days, and DST.
struct TaskMonthGrid {
    let month: Date
    let calendar: Calendar

    var firstDay: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    var days: [Date] {
        let weekday = calendar.component(.weekday, from: firstDay)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: firstDay) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var weekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
    func moving(by months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: firstDay) ?? firstDay
    }
    func contains(_ date: Date) -> Bool { calendar.isDate(date, equalTo: month, toGranularity: .month) }
}
