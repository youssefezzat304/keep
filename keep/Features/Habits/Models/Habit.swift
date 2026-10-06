import Foundation

enum HabitIcon: String, Codable, CaseIterable, Identifiable {
    case checkmark = "checkmark.seal.fill", book = "book.fill", exercise = "dumbbell.fill"
    case walk = "figure.walk", water = "drop.fill", leaf = "leaf.fill", sleep = "moon.fill"
    case music = "music.note", write = "pencil", study = "graduationcap.fill", heart = "heart.fill", sun = "sun.max.fill"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .checkmark: "Check-in"
        case .book: "Reading"
        case .exercise: "Exercise"
        case .walk: "Walking"
        case .water: "Water"
        case .leaf: "Mindfulness"
        case .sleep: "Sleep"
        case .music: "Music"
        case .write: "Writing"
        case .study: "Learning"
        case .heart: "Wellbeing"
        case .sun: "Morning"
        }
    }
}

enum HabitUnit: String, Codable, CaseIterable, Identifiable {
    case minutes, times
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var maximumTarget: Int { self == .minutes ? 1440 : 10000 }
}

enum HabitGoal: Codable, Equatable {
    case checkIn
    case amount(target: Int, unit: HabitUnit)
    var target: Int { if case .amount(let target, _) = self { return target }; return 1 }
    var isValid: Bool { if case .amount(let target, let unit) = self { return (1...unit.maximumTarget).contains(target) }; return true }
    var summary: String {
        switch self {
        case .checkIn: "Daily check-in"
        case .amount(let target, let unit): "\(target) \(unit == .minutes ? "min" : target == 1 ? "time" : "times") / day"
        }
    }
}

/// Raw values match Gregorian weekdays; display order is Monday through Sunday.
enum HabitWeekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    static let allCases: [HabitWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    var id: Int { rawValue }
    private static let civilCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    static func forDay(_ day: String) -> HabitWeekday? {
        guard let date = TaskDay.date(for: day, calendar: civilCalendar) else { return nil }
        return HabitWeekday(rawValue: civilCalendar.component(.weekday, from: date))
    }
    func title(calendar: Calendar) -> String { calendar.weekdaySymbols[rawValue - 1] }
    func shortTitle(calendar: Calendar) -> String { calendar.veryShortStandaloneWeekdaySymbols[rawValue - 1] }
}

struct Habit: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let icon: HabitIcon
    let startDay: String
    let endDay: String?
    let goal: HabitGoal
    var weekdays: [HabitWeekday] = HabitWeekday.allCases

    func isWithinRange(_ day: String) -> Bool { day >= startDay && endDay.map { day <= $0 } != false }
    func isScheduled(on day: String) -> Bool {
        guard isWithinRange(day), let weekday = HabitWeekday.forDay(day) else { return false }
        return weekdays.contains(weekday)
    }
    func frequencySummary(calendar: Calendar) -> String {
        weekdays.count == 7 ? "Every day" : weekdays.map { calendar.shortWeekdaySymbols[$0.rawValue - 1] }.joined(separator: ", ")
    }
    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && name == trimmed && name.count <= 80 && TaskDay.isValid(startDay) &&
            (endDay == nil || endDay.map { TaskDay.isValid($0) && $0 >= startDay } == true) && goal.isValid && !weekdays.isEmpty && Set(weekdays).count == weekdays.count
    }
}

// Older archives were daily habits. Missing frequency retains all seven days.
extension Habit {
    private enum CodingKeys: String, CodingKey { case id, name, icon, startDay, endDay, goal, weekdays }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        icon = try values.decode(HabitIcon.self, forKey: .icon)
        startDay = try values.decode(String.self, forKey: .startDay)
        endDay = try values.decodeIfPresent(String.self, forKey: .endDay)
        goal = try values.decode(HabitGoal.self, forKey: .goal)
        weekdays = try values.decodeIfPresent([HabitWeekday].self, forKey: .weekdays) ?? HabitWeekday.allCases
    }
}

struct HabitLog: Codable, Equatable {
    let habitID: UUID
    let dayID: String
    var amount: Int
}

struct HabitArchive: Codable, Equatable {
    var habits: [Habit] = []
    var logs: [HabitLog] = []
    var isValid: Bool {
        var ids: Set<UUID> = []
        guard habits.allSatisfy({ $0.isValid && ids.insert($0.id).inserted }) else { return false }
        let catalog = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        var days: [UUID: Set<String>] = [:]
        return logs.allSatisfy { log in
            guard let habit = catalog[log.habitID] else { return false }
            return TaskDay.isValid(log.dayID) && habit.isScheduled(on: log.dayID) &&
                (1...1_000_000).contains(log.amount) && (habit.goal != .checkIn || log.amount == 1) &&
                days[log.habitID, default: []].insert(log.dayID).inserted
        }
    }
}

enum HabitError: LocalizedError {
    case invalidName, duplicateName, invalidDates, invalidGoal, invalidFrequency, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a habit name with 1–80 characters."
        case .duplicateName: "A habit with this name already exists. Choose another name."
        case .invalidDates: "Choose valid dates, with the end on or after the start."
        case .invalidGoal: "Choose a positive daily target: up to 1,440 minutes or 10,000 times."
        case .invalidFrequency: "Choose at least one day of the week."
        case .unavailable: "Retry loading your saved habits before making changes."
        }
    }
}
