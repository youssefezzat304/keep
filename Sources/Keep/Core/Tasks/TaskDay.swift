import Foundation

/// Civil dates are stored as keys, so a timezone change never moves saved tasks to another day.
nonisolated enum TaskDay {
    static func id(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(for id: String, calendar: Calendar) -> Date? {
        guard id.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              Self.id(for: date, calendar: calendar) == id else { return nil }
        return date
    }

    static func isValid(_ id: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return false }
        calendar.timeZone = utc
        return date(for: id, calendar: calendar) != nil
    }
}

nonisolated struct TaskDaySelection {
    /// nil follows today's date as the app crosses midnight; browsing pins a civil date.
    private(set) var selectedID: String?

    func dayID(today: Date, calendar: Calendar) -> String {
        selectedID ?? TaskDay.id(for: today, calendar: calendar)
    }

    func date(today: Date, calendar: Calendar) -> Date {
        TaskDay.date(for: dayID(today: today, calendar: calendar), calendar: calendar) ?? today
    }

    mutating func select(_ date: Date, today: Date, calendar: Calendar) {
        let id = TaskDay.id(for: date, calendar: calendar)
        selectedID = id == TaskDay.id(for: today, calendar: calendar) ? nil : id
    }

    mutating func move(by days: Int, today: Date, calendar: Calendar) {
        guard let date = calendar.date(byAdding: .day, value: days, to: date(today: today, calendar: calendar)) else { return }
        select(date, today: today, calendar: calendar)
    }

    mutating func goToToday() { selectedID = nil }
}
