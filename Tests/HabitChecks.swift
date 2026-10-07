import Foundation
import Observation

private final class HabitChangeReading { var changed = false }

@main enum HabitChecks {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }
    static func date(_ id: String, _ calendar: Calendar) -> Date {
        guard let value = TaskDay.date(for: id, calendar: calendar) else { fatalError("Invalid fixture date") }
        return value
    }
    static func rejects(_ action: () throws -> Void, _ message: String) {
        do { try action(); expect(false, message) } catch { expect(true, message) }
    }
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            try probe(mode: CommandLine.arguments[1], suite: CommandLine.arguments[2])
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        guard let berlin = TimeZone(identifier: "Europe/Berlin") else { fatalError("Missing timezone") }
        calendar.timeZone = berlin
        calendar.locale = Locale(identifier: "en_GB")
        let today = date("2026-10-06", calendar)
        let store = HabitStore(calendar: calendar)
        expect(store.habits.isEmpty && store.archive.logs.isEmpty, "Fresh tracker has no fixtures")
        expect(store.calendar.firstWeekday == 2, "Weeks use Monday")
        let check = try store.add(name: "  Exercise \n", icon: .exercise, startDay: "2026-09-29", endDay: nil, goal: .checkIn)
        expect(check.name == "Exercise", "Trim names")
        let read = try store.add(name: "Read", icon: .book, startDay: "2026-10-02", endDay: "2026-10-06", goal: .amount(target: 20, unit: .minutes))
        let water = try store.add(name: "Water", icon: .water, startDay: "2026-10-01", endDay: nil, goal: .amount(target: 3, unit: .times))
        expect(store.habits.map(\.id) == [check.id, read.id, water.id], "Stable identities and creation order")
        rejects({ _ = try store.add(name: "éxercise", icon: .heart, startDay: "2026-10-06", endDay: nil, goal: .checkIn) }, "Reject case/diacritic duplicates")
        for name in [" \n ", String(repeating: "a", count: 81)] {
            rejects({ _ = try store.add(name: name, icon: .book, startDay: "2026-10-06", endDay: nil, goal: .checkIn) }, "Reject invalid names")
        }
        for (start, end) in [("2026-02-30", nil), ("2026-10-06", "2026-02-30"), ("2026-10-06", "2026-10-05")] {
            rejects({ _ = try store.add(name: "Invalid dates", icon: .book, startDay: start, endDay: end, goal: .checkIn) }, "Reject invalid range")
        }
        for goal in [HabitGoal.amount(target: 0, unit: .minutes), .amount(target: -1, unit: .times), .amount(target: 1441, unit: .minutes), .amount(target: 10001, unit: .times)] {
            rejects({ _ = try store.add(name: "Invalid goal", icon: .book, startDay: "2026-10-06", endDay: nil, goal: goal) }, "Reject impossible targets")
        }
        expect(HabitGoal.amount(target: 1440, unit: .minutes).isValid && HabitGoal.amount(target: 10000, unit: .times).isValid, "Target upper boundaries accepted")
        expect(read.isScheduled(on: "2026-10-02") && read.isScheduled(on: "2026-10-06"), "Start and end inclusive")
        expect(!read.isScheduled(on: "2026-10-01") && !read.isScheduled(on: "2026-10-07"), "Outside date range not due")
        expect(store.setAmount(1, habitID: check.id, on: "2026-10-06", today: today), "Check in")
        expect(store.isComplete(check, on: "2026-10-06") && store.completed(on: "2026-10-06") == 1, "Check-in counts once")
        expect(store.setAmount(1, habitID: check.id, on: "2026-10-06", today: today) && store.archive.logs.count == 1, "Repeated set does not duplicate progress")
        expect(store.setAmount(0, habitID: check.id, on: "2026-10-06", today: today) && store.archive.logs.isEmpty, "Clear check-in removes its log")
        expect(!store.setAmount(2, habitID: check.id, on: "2026-10-06", today: today), "Check-in accepts only zero/one")
        for (id, amount, habit) in [("2026-10-07", 1, check), ("2026-09-28", 1, check), ("2026-10-07", 20, read), ("2026-02-30", 1, check), ("2026-10-06", -1, read), ("2026-10-06", 1_000_001, read)] {
            expect(!store.setAmount(amount, habitID: habit.id, on: id, today: today), "Reject future, out-of-range, invalid and unsafe amounts")
        }
        expect(!store.setAmount(1, habitID: UUID(), on: "2026-10-06", today: today), "Stale identity cannot create orphan log")
        expect(store.setAmount(15, habitID: read.id, on: "2026-10-06", today: today), "Save partial minutes")
        expect(store.amount(for: read, on: "2026-10-06") == 15 && !store.isComplete(read, on: "2026-10-06"), "Partial target not counted complete")
        expect(store.setAmount(20, habitID: read.id, on: "2026-10-06", today: today) && store.isComplete(read, on: "2026-10-06"), "Exact target counts complete")
        expect(store.setAmount(27, habitID: read.id, on: "2026-10-06", today: today) && store.completed(on: "2026-10-06") == 1, "Exceeding target does not count twice")
        let reading = HabitChangeReading()
        withObservationTracking { _ = store.isComplete(read, on: "2026-10-06") } onChange: {
            MainActor.assumeIsolated { reading.changed = true }
        }
        expect(store.setAmount(18, habitID: read.id, on: "2026-10-06", today: today), "Correct a completed target to partial")
        expect(reading.changed && !store.isComplete(read, on: "2026-10-06"), "Visible completion queries invalidate after progress changes")
        expect(store.setAmount(27, habitID: read.id, on: "2026-10-06", today: today), "Restore completed target after correction")
        expect(store.setAmount(2, habitID: water.id, on: "2026-10-06", today: today) && !store.isComplete(water, on: "2026-10-06"), "Partial times target")
        expect(store.setAmount(3, habitID: water.id, on: "2026-10-06", today: today) && store.isComplete(water, on: "2026-10-06"), "Times target complete")
        _ = store.setAmount(1, habitID: check.id, on: "2026-10-06", today: today)
        expect(store.completed(on: "2026-10-06") == 3 && store.scheduled(on: "2026-10-06") == 3, "Aggregate counts habits, not units")
        expect(store.scheduled(on: "2026-10-01") == 2 && store.scheduled(on: "2026-10-07") == 2, "Daily scheduled counts respect both dates")
        for id in ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-03", "2026-10-04", "2026-10-05"] {
            expect(store.setAmount(1, habitID: check.id, on: id, today: today), "Backfill an eligible past day")
        }
        var stats = store.statistics(for: check, month: today, today: today)
        expect(stats.monthlyCompletions == 5 && stats.totalCompletions == 7, "Monthly and lifetime completed days")
        expect(stats.monthlyScheduled == 6 && abs(stats.monthlyRate - 5.0/6) < 0.00001, "Rate excludes future scheduled days")
        expect(stats.currentStreak == 4 && stats.bestStreak == 4, "Gap splits streaks across month boundary")
        _ = store.setAmount(0, habitID: check.id, on: "2026-10-06", today: today)
        stats = store.statistics(for: check, month: today, today: today)
        expect(stats.currentStreak == 3, "Today's incomplete check-in keeps yesterday's streak")
        _ = store.setAmount(0, habitID: check.id, on: "2026-10-05", today: today)
        stats = store.statistics(for: check, month: today, today: today)
        expect(stats.currentStreak == 0 && stats.bestStreak == 3, "Past correction updates current/best streak")
        let readStats = store.statistics(for: read, month: today, today: today)
        expect(readStats.monthlyScheduled == 5 && readStats.monthlyCompletions == 1 && readStats.monthlyRate == 0.2, "Rate respects start/end date")
        let ended = store.statistics(for: read, month: today, today: date("2026-10-08", calendar))
        expect(ended.currentStreak == 0 && ended.bestStreak == 1 && ended.monthlyScheduled == 5, "Ended habit retains history and best streak")
        let future = try store.add(name: "Next week", icon: .sun, startDay: "2026-10-12", endDay: nil, goal: .checkIn)
        let futureStats = store.statistics(for: future, month: today, today: today)
        expect(futureStats.monthlyRate == 0 && futureStats.monthlyScheduled == 0 && futureStats.currentStreak == 0, "Future habit has no invented history or rate")
        expect(store.statistics(for: check, month: date("2026-11-01", calendar), today: today).monthlyScheduled == 0, "Future month rate denominator zero")
        let days = HabitDates.monthGrid(containing: today, calendar: store.calendar)
        expect(days.count == 42 && Set(days.map { TaskDay.id(for: $0, calendar: calendar) }).count == 42, "Grid contains six distinct weeks")
        expect(TaskDay.id(for: days[0], calendar: calendar) == "2026-09-28", "Month aligned Monday")
        expect(HabitDates.monthDays(containing: date("2024-02-15", calendar), calendar: calendar).count == 29, "Leap February")
        expect(HabitDates.monthDays(containing: date("2025-02-15", calendar), calendar: calendar).count == 28, "Ordinary February")
        let week = HabitDates.weekDays(containing: date("2027-01-01", calendar), calendar: calendar)
        expect(TaskDay.id(for: week[0], calendar: calendar) == "2026-12-28" && TaskDay.id(for: week[6], calendar: calendar) == "2027-01-03", "Week crosses year boundary")
        for (id, hours) in [("2026-03-29", 23.0), ("2026-10-25", 25.0)] {
            let week = HabitDates.weekDays(containing: date(id, calendar), calendar: calendar)
            expect(week.count == 7 && Set(week.map { TaskDay.id(for: $0, calendar: calendar) }).count == 7, "DST week has distinct days")
            let midnight = calendar.startOfDay(for: date(id, calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { fatalError("Missing day") }
            expect(next.timeIntervalSince(midnight) == hours * 3600, "Calendar arithmetic handles DST")
            let dst = HabitStore(calendar: calendar)
            let h = try dst.add(name: "DST", icon: .walk, startDay: TaskDay.id(for: week[0], calendar: calendar), endDay: nil, goal: .checkIn)
            let last = date(TaskDay.id(for: next, calendar: calendar), calendar)
            for day in [week[5], week[6], next] { _ = dst.setAmount(1, habitID: h.id, on: TaskDay.id(for: day, calendar: calendar), today: last) }
            expect(dst.statistics(for: h, month: last, today: last).currentStreak == 3, "Streak uses civil days through DST")
        }
        var islamic = Calendar(identifier: .islamicCivil)
        islamic.timeZone = berlin
        let civil = HabitStore(calendar: islamic)
        expect(civil.calendar.identifier == .gregorian && TaskDay.id(for: today, calendar: civil.calendar) == "2026-10-06", "Archive uses Gregorian keys independent of system calendar")
        expect(HabitDates.weekdayLabels(calendar: store.calendar).count == 7, "Localized day headers")
        var ahead = store.archive
        ahead.logs.append(HabitLog(habitID: check.id, dayID: "2026-10-07", amount: 1))
        let clockMovedBack = HabitStore(archive: ahead, calendar: calendar)
        expect(clockMovedBack.statistics(for: check, month: today, today: today).totalCompletions == stats.totalCompletions, "Clock moving back excludes later saved completions from stats")
        expect(HabitDates.label(today, calendar: civil.calendar, style: .dateTime.year()).contains("2026"), "Labels share Gregorian calendar with storage")
        try persistenceChecks(archive: store.archive, today: today, calendar: calendar)
        try frequencyAndYearChecks(calendar: calendar)
        let suite = "keep.tests.habits.process.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        for mode in ["write", "read"] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [mode, suite]
            try child.run(); child.waitUntilExit()
            expect(child.terminationStatus == 0, "Progress survives separate process \(mode)")
        }
        print("Passed \(checks) habit checks")
    }
    static func frequencyAndYearChecks(calendar: Calendar) throws {
        let today = date("2026-10-06", calendar)
        let store = HabitStore(calendar: calendar)
        let habit = try store.add(name: "Exercise", icon: .exercise, startDay: "2026-09-28", endDay: nil, goal: .checkIn, weekdays: [.friday, .monday, .wednesday])
        expect(habit.weekdays == [.monday, .wednesday, .friday], "Frequency normalizes Monday-first order")
        expect(habit.isScheduled(on: "2026-10-05") && !habit.isScheduled(on: "2026-10-06"), "Only chosen weekdays are due")
        expect(!store.setAmount(1, habitID: habit.id, on: "2026-10-06", today: today), "Rest day cannot be checked in")
        rejects({ _ = try store.add(name: "No days", icon: .book, startDay: "2026-10-06", endDay: nil, goal: .checkIn, weekdays: []) }, "Reject empty frequency")
        rejects({ _ = try store.add(name: "Duplicate days", icon: .book, startDay: "2026-10-06", endDay: nil, goal: .checkIn, weekdays: [.monday, .monday]) }, "Reject repeated weekdays")
        for id in ["2026-09-28", "2026-09-30", "2026-10-02", "2026-10-05"] {
            expect(store.setAmount(1, habitID: habit.id, on: id, today: today), "Log a scheduled weekday")
        }
        let stats = store.statistics(for: habit, month: today, today: today)
        expect(stats.monthlyScheduled == 2 && stats.monthlyCompletions == 2 && stats.monthlyRate == 1, "Rate excludes weekday rest days")
        expect(stats.currentStreak == 4 && stats.bestStreak == 4, "Rest days preserve scheduled-check-in streak")
        expect(store.statistics(for: habit, month: today, today: date("2026-10-07", calendar)).currentStreak == 4, "Pending due day preserves prior streak")
        expect(store.statistics(for: habit, month: today, today: date("2026-10-08", calendar)).currentStreak == 0, "Missed scheduled day breaks streak on following rest day")
        let later = date("2026-10-09", calendar)
        _ = store.setAmount(1, habitID: habit.id, on: "2026-10-09", today: later)
        let laterStats = store.statistics(for: habit, month: later, today: later)
        expect(laterStats.currentStreak == 1 && laterStats.bestStreak == 4, "Gap starts new streak and retains best")
        let ended = Habit(id: UUID(), name: "Ended", icon: .exercise, startDay: "2026-10-01", endDay: "2026-10-05", goal: .checkIn, weekdays: [.monday, .friday])
        let endedStore = HabitStore(archive: HabitArchive(habits: [ended], logs: [HabitLog(habitID: ended.id, dayID: "2026-10-02", amount: 1), HabitLog(habitID: ended.id, dayID: "2026-10-05", amount: 1)]), calendar: calendar)
        expect(endedStore.statistics(for: ended, month: today, today: today).currentStreak == 0 && endedStore.statistics(for: ended, month: today, today: today).bestStreak == 2, "Ended weekly habit retains best but has no current streak")
        let mondays = HabitStore(calendar: calendar)
        let monday = try mondays.add(name: "Monday", icon: .write, startDay: "2026-03-23", endDay: nil, goal: .amount(target: 10, unit: .minutes), weekdays: [.monday])
        let afterDST = date("2026-03-30", calendar)
        for id in ["2026-03-23", "2026-03-30"] { _ = mondays.setAmount(10, habitID: monday.id, on: id, today: afterDST) }
        expect(mondays.statistics(for: monday, month: afterDST, today: afterDST).currentStreak == 2, "Once-weekly streak crosses DST")
        var invalid = habit
        invalid.weekdays = []
        expect(!invalid.isValid, "Archive rejects empty frequency")
        invalid.weekdays = [.monday, .monday]
        expect(!invalid.isValid, "Archive rejects duplicate frequency")
        expect(!HabitArchive(habits: [habit], logs: [HabitLog(habitID: habit.id, dayID: "2026-10-06", amount: 1)]).isValid, "Archive rejects rest-day logs")
        let encoded = try JSONEncoder().encode(store.archive)
        expect(tryDecoded(encoded).habits[0].weekdays == habit.weekdays && tryDecoded(encoded).isValid, "Frequency and progress round trip")
        let daily = Habit(id: UUID(), name: "Daily legacy", icon: .book, startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        let legacy = HabitArchive(habits: [daily], logs: [HabitLog(habitID: daily.id, dayID: "2026-10-06", amount: 1)])
        guard var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any],
              var habits = json["habits"] as? [[String: Any]] else { fatalError("Legacy fixture") }
        habits[0].removeValue(forKey: "weekdays")
        json["habits"] = habits
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let restored = tryDecoded(oldData)
        expect(restored == legacy && restored.isValid, "Pre-frequency habits preserve daily schedule and history")
        habits[0]["weekdays"] = [9]
        json["habits"] = habits
        let unknown = try JSONSerialization.data(withJSONObject: json)
        rejects({ _ = try JSONDecoder().decode(HabitArchive.self, from: unknown) }, "Unknown weekday rejected during decoding")
        for (year, expectedDays) in [(2026, 365), (2024, 366), (2012, 366)] {
            let origin = date("\(year)-06-15", calendar)
            let weeks = HabitDates.yearWeeks(containing: origin, calendar: calendar)
            let days = weeks.flatMap { $0 }.filter { calendar.component(.year, from: $0) == year }
            expect(days.count == expectedDays && Set(days.map { TaskDay.id(for: $0, calendar: calendar) }).count == expectedDays, "Annual grid contains every day exactly once")
            expect(weeks.allSatisfy { $0.count == 7 && calendar.component(.weekday, from: $0[0]) == 2 }, "Year columns are full Monday-first weeks")
            expect(TaskDay.id(for: days[0], calendar: calendar) == "\(year)-01-01" && TaskDay.id(for: days[expectedDays - 1], calendar: calendar) == "\(year)-12-31", "Annual grid covers Jan through Dec")
            expect(Set(days.filter { calendar.component(.day, from: $0) == 1 }.map { calendar.component(.month, from: $0) }).count == 12, "All twelve month labels represented")
        }
        expect(HabitDates.weeklyHeight(completions: 0) == 0, "Empty year weekly bars empty")
        expect(HabitDates.weeklyHeight(completions: 1) == 1, "Small positive weekly total remains visible")
        expect(HabitDates.weeklyHeight(completions: 4) == 4 && HabitDates.weeklyHeight(completions: 100) == 7, "Weekly bars count goals and cap at seven instead of scaling sparse history")
        let suite = "keep.tests.frequency.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = HabitPersistence(defaults: defaults)
        defaults.set(oldData, forKey: persistence.key)
        expect(HabitStore(persistence: persistence, calendar: calendar).archive == legacy, "Legacy frequency migration through real persistence")
        try persistence.save(store.archive)
        expect(HabitStore(persistence: persistence, calendar: calendar).archive == store.archive, "Scheduled habits and logs survive reload")
    }
    static func tryDecoded(_ data: Data) -> HabitArchive {
        do { return try JSONDecoder().decode(HabitArchive.self, from: data) }
        catch { fatalError("Unexpected fixture decode: \(error)") }
    }

    static func persistenceChecks(archive: HabitArchive, today: Date, calendar: Calendar) throws {
        let suite = "keep.tests.habits.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = HabitPersistence(defaults: defaults)
        let empty = try persistence.load()
        expect(empty.habits.isEmpty, "Missing archive is empty")
        let fresh = HabitStore(persistence: persistence, calendar: calendar)
        let definition = try fresh.add(name: "Before first log", icon: .sleep, startDay: "2026-10-06", endDay: nil, goal: .checkIn)
        let beforeLog = try persistence.load()
        expect(beforeLog.habits == [definition] && beforeLog.logs.isEmpty, "Definition persists before first check-in")
        try persistence.save(archive)
        let loaded = HabitStore(persistence: persistence, calendar: calendar)
        expect(loaded.archive == archive && loaded.canEdit, "Definitions and partial progress round trip")
        var tokyo = calendar
        guard let japan = TimeZone(identifier: "Asia/Tokyo") else { fatalError("Timezone") }
        tokyo.timeZone = japan
        let moved = HabitStore(persistence: persistence, calendar: tokyo)
        expect(moved.archive.logs.map(\.dayID) == archive.logs.map(\.dayID), "Timezone change doesn't move past logs")
        var invalid = archive
        invalid.habits.append(archive.habits[0])
        expect(!invalid.isValid, "Reject duplicate habit identities")
        rejects({ try persistence.save(invalid) }, "Invalid saves preserve earlier archive")
        let preserved = try persistence.load()
        expect(preserved == archive, "Invalid write preserves saved data")
        invalid = archive
        invalid.logs.append(archive.logs[0])
        expect(!invalid.isValid, "Reject duplicate habit/day logs")
        for log in [HabitLog(habitID: UUID(), dayID: "2026-10-06", amount: 1), HabitLog(habitID: archive.habits[0].id, dayID: "2026-02-30", amount: 1), HabitLog(habitID: archive.habits[0].id, dayID: "2026-09-28", amount: 1), HabitLog(habitID: archive.habits[0].id, dayID: "2026-09-29", amount: 2)] {
            expect(!HabitArchive(habits: archive.habits, logs: [log]).isValid, "Reject orphan, invalid, out-of-range and nonbinary logs")
        }
        let bytes = Data("corrupt saved habits".utf8)
        defaults.set(bytes, forKey: persistence.key)
        let broken = HabitStore(persistence: persistence, calendar: calendar)
        expect(broken.loadFailed && !broken.canEdit && broken.persistenceError != nil, "Corrupt load visibly blocks edits")
        rejects({ _ = try broken.add(name: "Don't overwrite", icon: .leaf, startDay: "2026-10-06", endDay: nil, goal: .checkIn) }, "Failed load blocks creation")
        expect(!broken.setAmount(1, habitID: archive.habits[0].id, on: "2026-10-06", today: today), "Failed load blocks progress")
        broken.retryPersistence()
        expect(defaults.data(forKey: persistence.key) == bytes && broken.loadFailed, "Retry preserves unrepaired saved bytes")
        try persistence.save(archive)
        broken.retryPersistence()
        expect(broken.canEdit && broken.archive == archive && broken.persistenceError == nil, "Retry recovers repaired archive")
        defaults.set(try JSONEncoder().encode(invalid), forKey: persistence.key)
        let badArchive = HabitStore(persistence: persistence, calendar: calendar)
        expect(badArchive.loadFailed && !badArchive.canEdit, "Decodable invalid archive also blocked")
        defaults.set("wrong type", forKey: persistence.key)
        expect(HabitStore(persistence: persistence).loadFailed, "Wrong defaults type not treated as empty")
    }
    static func probe(mode: String, suite: String) throws {
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Defaults") }
        let persistence = HabitPersistence(defaults: defaults)
        if mode == "write" {
            let store = HabitStore(persistence: persistence)
            let habit = try store.add(name: "Read", icon: .book, startDay: "2026-10-01", endDay: "2026-10-31", goal: .amount(target: 20, unit: .minutes), weekdays: [.tuesday, .thursday])
            _ = store.setAmount(15, habitID: habit.id, on: "2026-10-06", today: date("2026-10-06", store.calendar))
            expect(defaults.synchronize(), "Flush preferences for process probe")
        } else {
            let store = HabitStore(persistence: persistence)
            expect(store.habits.count == 1 && store.archive.logs.count == 1, "Relaunch retains definitions/logs")
            expect(store.habits[0].weekdays == [.tuesday, .thursday], "Weekday choices survive a separate process")
            expect(store.habits[0].goal == .amount(target: 20, unit: .minutes) && store.archive.logs[0].amount == 15, "Partial amount survives relaunch")
        }
    }
}
