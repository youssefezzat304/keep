import Foundation
import Observation

struct HabitPersistence {
    let defaults: UserDefaults
    let key: String
    init(defaults: UserDefaults = .standard, key: String = "keep.habits.v1") { self.defaults = defaults; self.key = key }
    func load() throws -> HabitArchive {
        guard defaults.object(forKey: key) != nil else { return HabitArchive() }
        guard let data = defaults.data(forKey: key) else { throw CocoaError(.coderReadCorrupt) }
        let archive = try JSONDecoder().decode(HabitArchive.self, from: data)
        guard archive.isValid else { throw CocoaError(.coderReadCorrupt) }
        return archive
    }
    func save(_ archive: HabitArchive) throws {
        guard archive.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(archive), forKey: key)
    }
}

struct HabitStatistics {
    let monthlyCompletions: Int
    let totalCompletions: Int
    let monthlyScheduled: Int
    let currentStreak: Int
    let bestStreak: Int
    var monthlyRate: Double { monthlyScheduled > 0 ? Double(monthlyCompletions) / Double(monthlyScheduled) : 0 }
}

@Observable final class HabitStore {
    private(set) var archive: HabitArchive
    // Derived query index keeps a long history from being scanned for every visible cell.
    private var progressByHabit: [UUID: [String: Int]] = [:]
    private(set) var loadFailed = false
    private(set) var persistenceError: String?
    var canEdit: Bool { !loadFailed }
    var habits: [Habit] { archive.habits }
    @ObservationIgnored private let persistence: HabitPersistence?
    @ObservationIgnored private let calendarSource: Calendar
    @ObservationIgnored private var needsSave = false
    @ObservationIgnored private var activityCache: (key: String, snapshot: HabitActivitySnapshot)?
    var calendar: Calendar {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendarSource.timeZone
        local.locale = calendarSource.locale
        local.firstWeekday = 2
        return local
    }

    init(archive: HabitArchive = HabitArchive(), persistence: HabitPersistence? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.archive = archive
        self.persistence = persistence
        calendarSource = calendar
        if let persistence {
            do { self.archive = try persistence.load() }
            catch { loadFailed = true; persistenceError = "Couldn’t load your saved habits. Retry before changing them." }
        }
        rebuildProgressIndex()
    }

    func activity(today: Date) -> HabitActivitySnapshot {
        _ = archive // Observe data changes even when the prepared snapshot is cached.
        let key = TaskDay.id(for: today, calendar: calendar) + calendar.timeZone.identifier + (calendar.locale?.identifier ?? "")
        if let cached = activityCache, cached.key == key { return cached.snapshot }
        let snapshot = HabitActivitySnapshot(archive: archive, today: today, calendar: calendar)
        activityCache = (key, snapshot)
        return snapshot
    }

    private func rebuildProgressIndex() {
        activityCache = nil
        progressByHabit = archive.logs.reduce(into: [:]) { index, log in
            index[log.habitID, default: [:]][log.dayID] = log.amount
        }
    }

    @discardableResult
    func add(name: String, icon: HabitIcon, startDay: String, endDay: String?, goal: HabitGoal, weekdays: [HabitWeekday] = HabitWeekday.allCases) throws -> Habit {
        guard canEdit else { throw HabitError.unavailable }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw HabitError.invalidName }
        guard !habits.contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { throw HabitError.duplicateName }
        guard TaskDay.isValid(startDay), endDay.map({ TaskDay.isValid($0) && $0 >= startDay }) != false else { throw HabitError.invalidDates }
        guard goal.isValid else { throw HabitError.invalidGoal }
        guard !weekdays.isEmpty, Set(weekdays).count == weekdays.count else { throw HabitError.invalidFrequency }
        let habit = Habit(id: UUID(), name: name, icon: icon, startDay: startDay, endDay: endDay, goal: goal, weekdays: HabitWeekday.allCases.filter { weekdays.contains($0) })
        activityCache = nil
        archive.habits.append(habit)
        save()
        return habit
    }

    func amount(for habit: Habit, on dayID: String) -> Int { progressByHabit[habit.id]?[dayID] ?? 0 }
    func isComplete(_ habit: Habit, on dayID: String) -> Bool { amount(for: habit, on: dayID) >= habit.goal.target && habit.isScheduled(on: dayID) }
    func completed(on dayID: String) -> Int { habits.filter { isComplete($0, on: dayID) }.count }
    func scheduled(on dayID: String) -> Int { habits.filter { $0.isScheduled(on: dayID) }.count }

    @discardableResult
    func setAmount(_ amount: Int, habitID: UUID, on dayID: String, today: Date = .now) -> Bool {
        guard canEdit, TaskDay.isValid(dayID), dayID <= TaskDay.id(for: today, calendar: calendar),
              let habit = habits.first(where: { $0.id == habitID }), habit.isScheduled(on: dayID),
              (0...1_000_000).contains(amount), habit.goal != .checkIn || amount <= 1 else { return false }
        activityCache = nil
        archive.logs.removeAll { $0.habitID == habitID && $0.dayID == dayID }
        if amount > 0 { archive.logs.append(HabitLog(habitID: habitID, dayID: dayID, amount: amount)) }
        progressByHabit[habitID, default: [:]][dayID] = amount > 0 ? amount : nil
        save()
        return true
    }

    func retryPersistence() {
        if loadFailed, let persistence {
            do {
                archive = try persistence.load()
                rebuildProgressIndex()
                loadFailed = false
                persistenceError = nil
            }
            catch { persistenceError = "Couldn’t load your saved habits. Retry before changing them." }
        } else if needsSave { save() }
    }

    func statistics(for habit: Habit, month: Date, today: Date) -> HabitStatistics {
        let todayID = TaskDay.id(for: today, calendar: calendar)
        let completedDays = progressByHabit[habit.id, default: [:]].filter { $0.value >= habit.goal.target && $0.key <= todayID }.map(\.key).sorted()
        let monthDays = HabitDates.monthDays(containing: month, calendar: calendar).map { TaskDay.id(for: $0, calendar: calendar) }
        let eligible = Set(monthDays.filter { $0 <= todayID && habit.isScheduled(on: $0) })
        let done = Set(completedDays)
        var best = 0, running = 0
        var previousID: String?
        for id in completedDays {
            guard let date = TaskDay.date(for: id, calendar: calendar) else { continue }
            let expectedPrevious = previousScheduledDay(before: date, habit: habit).map { TaskDay.id(for: $0, calendar: calendar) }
            running = previousID != nil && expectedPrevious == previousID ? running + 1 : 1
            best = max(best, running)
            previousID = id
        }
        var current = 0
        if habit.isWithinRange(todayID) {
            var cursor: Date? = calendar.startOfDay(for: today)
            if !habit.isScheduled(on: todayID) || !done.contains(todayID) {
                cursor = previousScheduledDay(before: today, habit: habit)
            }
            while let date = cursor, done.contains(TaskDay.id(for: date, calendar: calendar)) {
                current += 1
                cursor = previousScheduledDay(before: date, habit: habit)
            }
        }
        return HabitStatistics(monthlyCompletions: completedDays.filter { eligible.contains($0) }.count,
            totalCompletions: completedDays.count, monthlyScheduled: eligible.count, currentStreak: current, bestStreak: best)
    }

    private func previousScheduledDay(before date: Date, habit: Habit) -> Date? {
        for offset in 1...7 {
            guard let earlier = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date)) else { return nil }
            let id = TaskDay.id(for: earlier, calendar: calendar)
            if id < habit.startDay { return nil }
            if habit.isScheduled(on: id) { return earlier }
        }
        return nil
    }

    private func save() {
        guard let persistence else { return }
        needsSave = true
        do { try persistence.save(archive); needsSave = false; persistenceError = nil }
        catch { persistenceError = "Couldn’t save your habits. Your changes are still here; retry saving." }
    }
}
