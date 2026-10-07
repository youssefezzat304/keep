import Foundation
import Observation

private final class ChangeFlag { var changed = false }

@main enum HabitTaskChecks {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard value() else { fatalError(label) }
    }
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            try probe(mode: CommandLine.arguments[1], suite: CommandLine.arguments[2])
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.locale = Locale(identifier: "en_GB")
        guard let today = TaskDay.date(for: "2026-10-06", calendar: calendar) else { fatalError("Date") }
        let suite = "keep.tests.habit-tasks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let habitPersistence = HabitPersistence(defaults: defaults)
        let taskPersistence = TaskPersistence(defaults: defaults)
        let habits = HabitStore(persistence: habitPersistence, calendar: calendar)
        let daily = try habits.add(name: "Read", icon: .book, startDay: "2026-10-01", endDay: nil, goal: .amount(target: 20, unit: .minutes))
        let weekly = try habits.add(name: "Exercise", icon: .exercise, startDay: "2026-10-05", endDay: "2026-10-12", goal: .checkIn, weekdays: [.monday, .wednesday, .friday])
        let tasks = DailyTaskStore(persistence: taskPersistence, calendar: calendar, habits: habits)
        expect(tasks.tasks(on: "2026-10-06").map(\.title) == ["Read"], "Today's due habit appears automatically")
        expect(Set(tasks.tasks(on: "2026-10-07").map(\.title)) == Set(["Read", "Exercise"]), "Future selected weekdays are planned")
        expect(tasks.tasks(on: "2026-10-05").count == 2, "Past due habits appear")
        expect(tasks.tasks(on: "2026-09-30").isEmpty, "Start date respected")
        expect(tasks.tasks(on: "2026-10-14").count == 1, "Inclusive end date respected")
        expect(tasks.tasks(on: "2026-02-30").isEmpty, "Invalid date has no projected tasks")
        expect(tasks.archive.days.isEmpty, "Recurring rows are derived rather than duplicated in task archive")
        let projected = tasks.tasks(on: "2026-10-06")[0]
        expect(projected.id == daily.id && projected.habitID == daily.id, "Stable habit origin")
        expect(tasks.tasks(on: "2026-10-07").first?.id == projected.id, "Identity stays stable across days")
        tasks.add("Read", on: "2026-10-06")
        expect(tasks.tasks(on: "2026-10-06").count == 2, "Same-title manual task stays independent")
        let ordinary = tasks.tasks(on: "2026-10-06")[0]
        expect(ordinary.habitID == nil, "Manual task carries no habit origin")
        tasks.setComplete(true, taskID: ordinary.id, on: "2026-10-06")
        expect(!habits.isComplete(daily, on: "2026-10-06"), "Manual completion never changes habit")
        tasks.setComplete(true, taskID: daily.id, on: "2026-10-06", habitID: daily.id, today: today)
        expect(habits.amount(for: daily, on: "2026-10-06") == 20, "Habit task completion meets amount target")
        expect(tasks.tasks(on: "2026-10-06")[1].isComplete, "Completion appears in Tasks")
        expect(habits.activity(today: today).total == 1, "Activity updates from task completion")
        let flag = ChangeFlag()
        withObservationTracking { _ = tasks.tasks(on: "2026-10-06") } onChange: {
            MainActor.assumeIsolated { flag.changed = true }
        }
        habits.setAmount(12, habitID: daily.id, on: "2026-10-06", today: today)
        expect(flag.changed && !tasks.tasks(on: "2026-10-06")[1].isComplete, "Tracker edits invalidate Tasks and partial progress stays incomplete")
        expect(habits.activity(today: today).total == 0, "Prepared activity invalidates with log changes")
        tasks.setComplete(false, taskID: daily.id, on: "2026-10-06", habitID: daily.id, today: today)
        expect(habits.amount(for: daily, on: "2026-10-06") == 0, "Unchecking clears habit progress")
        tasks.setComplete(true, taskID: weekly.id, on: "2026-10-05", habitID: weekly.id, today: today)
        expect(habits.isComplete(weekly, on: "2026-10-05"), "Past due check-in can be corrected from Tasks")
        tasks.setComplete(true, taskID: weekly.id, on: "2026-10-06", habitID: weekly.id, today: today)
        expect(!habits.isComplete(weekly, on: "2026-10-06"), "Rest-day action rejected")
        tasks.setComplete(true, taskID: daily.id, on: "2026-10-07", habitID: daily.id, today: today)
        expect(!habits.isComplete(daily, on: "2026-10-07"), "Future habit completion blocked")
        expect(!tasks.canComplete(projected, on: "2026-10-07", today: today), "Future habit checkbox disabled")
        expect(tasks.canComplete(ordinary, on: "2026-10-07", today: today), "Ordinary planned-task behavior preserved")
        tasks.remove(taskID: daily.id, on: "2026-10-06", habitID: daily.id)
        expect(tasks.tasks(on: "2026-10-06").count == 1, "Deleting habit task hides only this day")
        expect(tasks.tasks(on: "2026-10-07").count == 2 && habits.habits.count == 2, "Hiding preserves schedule and definition")
        tasks.setComplete(true, taskID: daily.id, on: "2026-10-06", habitID: daily.id, today: today)
        expect(!habits.isComplete(daily, on: "2026-10-06"), "Stale hidden row cannot set progress")
        let reloadedHabits = HabitStore(persistence: habitPersistence, calendar: calendar)
        let reloadedTasks = DailyTaskStore(persistence: taskPersistence, calendar: calendar, habits: reloadedHabits)
        expect(reloadedTasks.tasks(on: "2026-10-06").count == 1, "Hidden occurrence survives reload")
        expect(reloadedTasks.tasks(on: "2026-10-05").first(where: { $0.habitID == weekly.id })?.isComplete == true, "Shared habit completion survives reload")
        expect(reloadedTasks.archive.days.values.flatMap { $0 }.allSatisfy { $0.habitID == nil }, "Task storage never copies habit completion")
        let legacy = Data("{\"days\":{}}".utf8)
        let legacyArchive = try JSONDecoder().decode(TaskArchive.self, from: legacy)
        expect(legacyArchive.hiddenHabitIDs.isEmpty, "Older task archives migrate without hidden occurrences")
        defaults.set(Data("{\"days\":{},\"hiddenHabitIDs\":{\"bad-date\":[]}}".utf8), forKey: taskPersistence.key)
        let blockedTasks = DailyTaskStore(persistence: taskPersistence, calendar: calendar, habits: habits)
        let saved = defaults.data(forKey: taskPersistence.key)
        expect(blockedTasks.loadFailed, "Invalid occurrence dates protect archive")
        blockedTasks.remove(taskID: daily.id, on: "2026-10-07", habitID: daily.id)
        blockedTasks.setComplete(true, taskID: daily.id, on: "2026-10-06", habitID: daily.id, today: today)
        expect(defaults.data(forKey: taskPersistence.key) == saved && !habits.isComplete(daily, on: "2026-10-06"), "Blocked task actions preserve both archives")
        defaults.set(Data("bad".utf8), forKey: habitPersistence.key)
        let blockedHabits = HabitStore(persistence: habitPersistence, calendar: calendar)
        let ordinaryOnly = DailyTaskStore(archive: TaskArchive(days: ["2026-10-06": [ordinary]]), calendar: calendar, habits: blockedHabits)
        expect(ordinaryOnly.tasks(on: "2026-10-06").count == 1, "Invalid habit archive preserves manual tasks")
        expect(!ordinaryOnly.canComplete(projected, on: "2026-10-06", today: today), "Invalid habit archive blocks habit actions")
        for id in ["2026-10-05", "2026-10-07", "2027-10-06", "invalid"] {
            expect(!tasks.canStartTimers(on: id, today: today), "Only Today can launch timers")
        }
        expect(tasks.canStartTimers(on: "2026-10-06", today: today), "Today can launch timers")
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { fatalError("Tomorrow") }
        expect(!tasks.canStartTimers(on: "2026-10-06", today: tomorrow), "Stale day loses timer actions at midnight")
        let collision = FocusTask(id: daily.id, title: "Independent task", isComplete: true)
        let collidingTasks = DailyTaskStore(archive: TaskArchive(days: ["2026-10-07": [collision]]), calendar: calendar, habits: habits)
        let collisionRows = collidingTasks.tasks(on: "2026-10-07")
        expect(Set(collisionRows.map(\.listID)).count == collisionRows.count, "Habit and manual task identities are separate even if UUIDs coincide")
        let adding = ChangeFlag()
        withObservationTracking { _ = tasks.tasks(on: "2026-10-06") } onChange: { MainActor.assumeIsolated { adding.changed = true } }
        _ = try habits.add(name: "Future plan", icon: .sun, startDay: "2026-10-07", endDay: nil, goal: .checkIn)
        expect(adding.changed && tasks.tasks(on: "2026-10-07").count == 3, "New definitions automatically refresh task projection")
        expect(tasks.tasks(on: "2026-10-06").count == 1, "Future habit does not appear early")
        let snapshot = habits.activity(today: today)
        expect(snapshot.weeks.count == 53 && snapshot.year == 2026 && snapshot.total == 1, "Prepared current-year data keeps exact counts")
        expect(snapshot.weeks.flatMap(\.days).filter(\.inYear).count == 365, "Prepared view includes every civil day")
        let first = ContinuousClock.now
        for _ in 0..<1000 { _ = habits.activity(today: today) }
        print("1000 cached annual snapshot reads: \(first.duration(to: .now))")
        let processSuite = "keep.tests.habit-tasks.process.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: processSuite)?.removePersistentDomain(forName: processSuite) }
        for mode in ["write", "read"] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [mode, processSuite]
            try child.run()
            child.waitUntilExit()
            expect(child.terminationStatus == 0, "Separate-process habit/task \(mode)")
        }
        print("Passed \(checks) habit/task integration checks")
    }
    static func probe(mode: String, suite: String) throws {
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Defaults") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let today = TaskDay.date(for: "2026-10-06", calendar: calendar) else { fatalError("Date") }
        let habits = HabitStore(persistence: HabitPersistence(defaults: defaults), calendar: calendar)
        let tasks = DailyTaskStore(persistence: TaskPersistence(defaults: defaults), calendar: calendar, habits: habits)
        if mode == "write" {
            let habit = try habits.add(name: "Exercise", icon: .exercise, startDay: "2026-10-05", endDay: nil, goal: .checkIn, weekdays: [.monday, .tuesday])
            tasks.setComplete(true, taskID: habit.id, on: "2026-10-05", habitID: habit.id, today: today)
            tasks.remove(taskID: habit.id, on: "2026-10-06", habitID: habit.id)
            expect(defaults.synchronize(), "Flush isolated archives")
        } else {
            expect(tasks.tasks(on: "2026-10-06").isEmpty, "Hidden day survives app relaunch")
            expect(tasks.tasks(on: "2026-10-05").first?.isComplete == true, "Habit completion survives app relaunch")
            expect(tasks.tasks(on: "2026-10-07").isEmpty && tasks.tasks(on: "2026-10-12").count == 1, "Rest and future due days survive app relaunch")
        }
    }

}
