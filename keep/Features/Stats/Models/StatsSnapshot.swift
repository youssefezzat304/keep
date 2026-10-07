import Foundation

nonisolated enum StatsPeriod: String, CaseIterable, Sendable {
    case week, month, year, custom
    var title: String { rawValue.capitalized }
}

nonisolated struct StatsQuery: Equatable, Sendable {
    var period: StatsPeriod = .week
    var anchor: Date?
    var customStart: Date = .now
    var customEnd: Date = .now
    var projectID: String?
    /// nil means all; the picker never commits an empty selection.
    var taskKeys: Set<String>?

    static func taskKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    func range(now: Date, calendar: Calendar) -> StatsRange {
        let date = anchor ?? now
        let interval: DateInterval?
        switch period {
        case .week: interval = calendar.dateInterval(of: .weekOfYear, for: date)
        case .month: interval = calendar.dateInterval(of: .month, for: date)
        case .year: interval = calendar.dateInterval(of: .year, for: date)
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.startOfDay(for: customEnd)
            return StatsRange(start: start, end: calendar.date(byAdding: .day, value: 1, to: end) ?? end)
        }
        return StatsRange(start: interval?.start ?? calendar.startOfDay(for: date), end: interval?.end ?? date)
    }

    mutating func move(_ direction: Int, now: Date, calendar: Calendar) {
        let current = range(now: now, calendar: calendar)
        if period == .custom {
            let count = max(1, calendar.dateComponents([.day], from: current.start, to: current.end).day ?? 1)
            if let start = calendar.date(byAdding: .day, value: count * direction, to: customStart),
               let end = calendar.date(byAdding: .day, value: count * direction, to: customEnd),
               calendar.startOfDay(for: end) <= calendar.startOfDay(for: now) {
                customStart = start; customEnd = end
            }
        } else {
            let component: Calendar.Component = period == .week ? .weekOfYear : period == .month ? .month : .year
            if let next = calendar.date(byAdding: component, value: direction, to: current.start), next <= now { anchor = next }
        }
    }
}

nonisolated struct StatsRange: Equatable, Sendable {
    let start: Date
    /// Exclusive civil-day boundary.
    let end: Date
    func endDay(calendar: Calendar) -> Date { calendar.date(byAdding: .day, value: -1, to: end) ?? start }
    func title(calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = calendar.locale
        formatter.dateFormat = "d MMM yyyy"
        return "\(formatter.string(from: start)) – \(formatter.string(from: endDay(calendar: calendar)))"
    }
}

/// Sendable values deliberately separate background calculations from observable store ownership.
nonisolated struct StatsInput: Sendable {
    struct Project: Identifiable, Sendable {
        let id: String
        let name: String
        let accent: String
        let deleted: Bool
    }
    struct Session: Sendable {
        let projectID: String
        let task: String
        let dayID: String
        let start: Date
        let end: Date
        let timeZoneID: String
    }
    struct Completion: Sendable {
        let projectID: String
        let task: String
        let dayID: String
        let date: Date
    }
    struct Entry: Sendable { let projectID: String; let dayID: String; let seconds: Double }
    struct TaskDay: Sendable { let dayID: String; let total: Int; let completed: Int }
    struct Habit: Identifiable, Sendable {
        let id: UUID
        let name: String
        let icon: String
        let start: String
        let end: String?
        let weekdays: Set<Int>
        let target: Int
        let progress: [String: Int]
        func scheduled(_ id: String, calendar: Calendar) -> Bool {
            guard id >= start, end.map({ id <= $0 }) ?? true, let date = StatsSnapshot.date(id, calendar: calendar) else { return false }
            return weekdays.contains(calendar.component(.weekday, from: date))
        }
    }
    let query: StatsQuery
    let now: Date
    let calendar: Calendar
    let projects: [Project]
    let sessions: [Session]
    let completions: [Completion]
    let historyStartedAt: Date?
    let entries: [Entry]
    let tasks: [TaskDay]
    let habits: [Habit]
}

nonisolated struct StatsSnapshot: Sendable {
    struct Bucket: Identifiable, Sendable {
        let id: String
        let date: Date
        let label: String
        var seconds: Double
    }
    struct Distribution: Identifiable, Sendable {
        let id: String
        let name: String
        let projectID: String
        let taskKey: String?
        let accent: String
        var seconds: Double
    }
    struct Habit: Identifiable, Sendable {
        let id: UUID
        let name: String
        let icon: String
        let completed: Int
        let due: Int
        let currentStreak: Int
        let bestStreak: Int
    }
    let range: StatsRange
    let total: Double
    let previousTotal: Double
    let activeDays: Int
    var average: Double { activeDays == 0 ? 0 : total / Double(activeDays) }
    let pomodoros: Int
    let pomodoroCoverage: Date?
    let pomodorosAvailable: Bool
    let adjustedTotal: Double
    let buckets: [Bucket]
    let distribution: [Distribution]
    let weekdays: [Double]
    let hours: [Double]
    let tasksCompleted: Int
    let tasksTotal: Int
    let habits: [Habit]
    var habitsCompleted: Int { habits.reduce(0) { $0 + $1.completed } }
    var habitsDue: Int { habits.reduce(0) { $0 + $1.due } }
    let weeklyGoalSeconds: Double
    let currentStreak: Int
    let bestStreak: Int

    static func calendar(_ source: Calendar) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = source.timeZone; value.locale = source.locale; value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }
    static func dayID(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func date(_ id: String, calendar: Calendar) -> Date? {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
    private static func days(_ range: StatsRange, calendar: Calendar) throws -> [Date] {
        var result: [Date] = [], cursor = range.start
        while cursor < range.end {
            try Task.checkCancellation()
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }

    static func make(_ input: StatsInput) throws -> StatsSnapshot {
        let calendar = calendar(input.calendar)
        let query = input.query, now = input.now
        let range = query.range(now: now, calendar: calendar)
        let startID = dayID(range.start, calendar: calendar)
        let endID = dayID(range.endDay(calendar: calendar), calendar: calendar)
        let todayID = dayID(now, calendar: calendar)
        let effectiveEnd = min(endID, todayID)
        let rangeDays = try days(range, calendar: calendar)
        func matches(_ project: String, _ task: String) -> Bool {
            (query.projectID == nil || project == query.projectID) && (query.taskKeys?.contains(StatsQuery.taskKey(task)) ?? true)
        }
        let projectMap = Dictionary(uniqueKeysWithValues: input.projects.map { ($0.id, $0) })
        var daily: [String: Double] = [:], distribution: [String: Distribution] = [:]
        var weekdays = Array(repeating: 0.0, count: 7), hours = Array(repeating: 0.0, count: 24)
        let week = StatsQuery().range(now: now, calendar: calendar)
        let weekStart = dayID(week.start, calendar: calendar), weekEnd = dayID(week.endDay(calendar: calendar), calendar: calendar)
        var weeklyGoalSeconds = 0.0
        let previous = comparisonRange(query: query, range: range, now: now, calendar: calendar)
        let previousStart = dayID(previous.range.start, calendar: calendar)
        let previousEnd = dayID(previous.range.endDay(calendar: calendar), calendar: calendar)
        var previousTotal = 0.0
        for session in input.sessions {
            try Task.checkCancellation()
            let end = min(session.end, now)
            let seconds = max(0, end.timeIntervalSince(session.start))
            if session.dayID >= weekStart && session.dayID <= min(weekEnd, todayID) { weeklyGoalSeconds += seconds }
            guard matches(session.projectID, session.task) else { continue }
            if session.dayID >= previousStart && session.dayID <= previousEnd {
                var previousSeconds = session.end.timeIntervalSince(session.start)
                if session.dayID == previousEnd, let wall = previous.wallCutoff {
                    var local = calendar
                    local.timeZone = TimeZone(identifier: session.timeZoneID) ?? calendar.timeZone
                    if let day = date(previousEnd, calendar: local),
                       let cutoff = local.date(bySettingHour: wall.hour ?? 0, minute: wall.minute ?? 0, second: wall.second ?? 0, of: day) {
                        previousSeconds = max(0, min(session.end, cutoff).timeIntervalSince(session.start))
                    }
                }
                previousTotal += max(0, previousSeconds)
            }
            // Keep prior days too, so a current streak may start before the displayed range.
            if session.dayID <= effectiveEnd { daily[session.dayID, default: 0] += seconds }
            guard session.dayID >= startID && session.dayID <= effectiveEnd, seconds > 0 else { continue }
            let key = query.projectID == nil ? session.projectID : StatsQuery.taskKey(session.task)
            let project = projectMap[session.projectID]
            if distribution[key] == nil {
                distribution[key] = Distribution(id: key, name: query.projectID == nil ? (project?.name ?? "No project") : (session.task.isEmpty ? "Unnamed task" : session.task),
                    projectID: session.projectID, taskKey: query.projectID == nil ? nil : key, accent: project?.accent ?? "neutral", seconds: 0)
            }
            distribution[key]?.seconds += seconds
            if let day = date(session.dayID, calendar: calendar) { weekdays[(calendar.component(.weekday, from: day) + 5) % 7] += seconds }
            var local = calendar
            local.timeZone = TimeZone(identifier: session.timeZoneID) ?? calendar.timeZone
            var cursor = session.start
            while cursor < end {
                try Task.checkCancellation()
                guard let hour = local.dateInterval(of: .hour, for: cursor), hour.end > cursor else { break }
                let stop = min(hour.end, end)
                hours[local.component(.hour, from: cursor)] += stop.timeIntervalSince(cursor)
                cursor = stop
            }
        }
        let selectedDaily = daily.filter { $0.key >= startID && $0.key <= effectiveEnd && $0.value > 0 }
        let total = selectedDaily.values.reduce(0, +)
        let grouping: Calendar.Component = query.period == .year || (query.period == .custom && rangeDays.count > 180) ? .month : query.period == .custom && rangeDays.count > 31 ? .weekOfYear : .day
        var buckets: [Bucket] = [], bucketIndices: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = calendar.locale
        formatter.dateFormat = grouping == .month ? "MMM yyyy" : "d MMM"
        for day in rangeDays {
            let bucketDate = max(range.start, calendar.dateInterval(of: grouping, for: day)?.start ?? day)
            let key = dayID(bucketDate, calendar: calendar)
            if bucketIndices[key] == nil {
                bucketIndices[key] = buckets.count
                buckets.append(Bucket(id: key, date: bucketDate, label: formatter.string(from: bucketDate), seconds: 0))
            }
            if let index = bucketIndices[key] { buckets[index].seconds += selectedDaily[dayID(day, calendar: calendar), default: 0] }
        }
        let completed = input.completions.filter { $0.dayID >= startID && $0.dayID <= effectiveEnd && $0.date <= now && matches($0.projectID, $0.task) }.count
        let adjusted = input.entries.filter { $0.dayID >= startID && $0.dayID <= effectiveEnd && (query.projectID == nil || $0.projectID == query.projectID) }.reduce(0) { $0 + $1.seconds }
        let taskDays = input.tasks.filter { $0.dayID >= startID && $0.dayID <= effectiveEnd }
        let streak = try focusStreak(daily: daily, startID: startID, endID: effectiveEnd, todayID: todayID, calendar: calendar)
        var habitRows: [Habit] = []
        for habit in input.habits {
            try Task.checkCancellation()
            let due = rangeDays.map { dayID($0, calendar: calendar) }.filter { $0 <= effectiveEnd && habit.scheduled($0, calendar: calendar) }
            let complete = Set(habit.progress.filter { $0.value >= habit.target && $0.key <= effectiveEnd }.map(\.key))
            var best = 0, run = 0
            for day in due { run = complete.contains(day) ? run + 1 : 0; best = max(best, run) }
            var current = 0
            if effectiveEnd >= habit.start && (habit.end.map { effectiveEnd <= $0 } ?? true), var cursor = date(effectiveEnd, calendar: calendar) {
                // Only actual today is allowed to remain pending.
                if effectiveEnd == todayID && habit.scheduled(effectiveEnd, calendar: calendar) && !complete.contains(effectiveEnd) {
                    cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                }
                while dayID(cursor, calendar: calendar) >= habit.start {
                    try Task.checkCancellation()
                    let id = dayID(cursor, calendar: calendar)
                    if habit.scheduled(id, calendar: calendar) {
                        guard complete.contains(id) else { break }
                        current += 1
                    }
                    guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
                    cursor = previous
                }
            }
            habitRows.append(Habit(id: habit.id, name: habit.name, icon: habit.icon, completed: due.filter { complete.contains($0) }.count, due: due.count, currentStreak: current, bestStreak: best))
        }
        return StatsSnapshot(range: range, total: total, previousTotal: previousTotal, activeDays: selectedDaily.count,
            pomodoros: completed, pomodoroCoverage: input.historyStartedAt,
            pomodorosAvailable: input.historyStartedAt.map { dayID($0, calendar: calendar) <= effectiveEnd } ?? false,
            adjustedTotal: adjusted, buckets: buckets,
            distribution: distribution.values.sorted { $0.seconds == $1.seconds ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.seconds > $1.seconds },
            weekdays: weekdays, hours: hours, tasksCompleted: taskDays.reduce(0) { $0 + $1.completed }, tasksTotal: taskDays.reduce(0) { $0 + $1.total },
            habits: habitRows, weeklyGoalSeconds: weeklyGoalSeconds, currentStreak: streak.current, bestStreak: streak.best)
    }

    private static func comparisonRange(query: StatsQuery, range: StatsRange, now: Date, calendar: Calendar) -> (range: StatsRange, wallCutoff: DateComponents?) {
        let count = calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1
        let component: Calendar.Component = query.period == .week ? .weekOfYear : query.period == .month ? .month : query.period == .year ? .year : .day
        let previousStart = calendar.date(byAdding: component, value: query.period == .custom ? -count : -1, to: range.start) ?? range.start
        let previousEnd = query.period == .custom ? range.start : calendar.date(byAdding: component, value: 1, to: previousStart) ?? range.start
        guard now >= range.start && now < range.end else { return (StatsRange(start: previousStart, end: previousEnd), nil) }
        let elapsedDays = calendar.dateComponents([.day], from: range.start, to: calendar.startOfDay(for: now)).day ?? 0
        let cutoffDay = calendar.date(byAdding: .day, value: elapsedDays, to: previousStart) ?? previousStart
        guard cutoffDay < previousEnd else { return (StatsRange(start: previousStart, end: previousEnd), nil) }
        let exclusive = min(previousEnd, calendar.date(byAdding: .day, value: 1, to: cutoffDay) ?? previousEnd)
        return (StatsRange(start: previousStart, end: exclusive), calendar.dateComponents([.hour, .minute, .second], from: now))
    }

    private static func focusStreak(daily: [String: Double], startID: String, endID: String, todayID: String, calendar: Calendar) throws -> (current: Int, best: Int) {
        let active = daily.filter { $0.value > 0 }.map(\.key).sorted()
        var best = 0, run = 0, prior: Date?
        for id in active where id >= startID && id <= endID {
            try Task.checkCancellation()
            guard let day = date(id, calendar: calendar) else { continue }
            run = prior.flatMap { calendar.dateComponents([.day], from: $0, to: day).day } == 1 ? run + 1 : 1
            best = max(best, run); prior = day
        }
        guard var cursor = date(endID, calendar: calendar) else { return (0, best) }
        if endID == todayID && daily[endID, default: 0] == 0 { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        var current = 0
        while daily[dayID(cursor, calendar: calendar), default: 0] > 0 {
            try Task.checkCancellation()
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        return (current, best)
    }
}
