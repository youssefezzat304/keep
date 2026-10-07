import Foundation

@main enum DailyTaskChecks {
    static var checks = 0

    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3 {
            try persistenceProbe(mode: CommandLine.arguments[1], suite: CommandLine.arguments[2])
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        guard let berlin = TimeZone(identifier: "Europe/Berlin") else { fatalError("Missing timezone") }
        calendar.timeZone = berlin
        let today = date(2026, 10, 5, calendar: calendar)
        let tomorrow = date(2026, 10, 6, calendar: calendar)
        var selection = TaskDaySelection()
        expect(selection.dayID(today: today, calendar: calendar) == "2026-10-05", "Initially show today")
        selection.move(by: -1, today: today, calendar: calendar)
        expect(selection.dayID(today: today, calendar: calendar) == "2026-10-04", "Navigate to yesterday")
        selection.move(by: 2, today: today, calendar: calendar)
        expect(selection.dayID(today: today, calendar: calendar) == "2026-10-06", "Navigate to tomorrow")
        selection.select(date(2031, 7, 18, calendar: calendar), today: today, calendar: calendar)
        expect(selection.dayID(today: today, calendar: calendar) == "2031-07-18", "Jump to a specific future date")
        selection.select(date(2024, 2, 29, calendar: calendar), today: today, calendar: calendar)
        expect(selection.dayID(today: tomorrow, calendar: calendar) == "2024-02-29", "Browsing stays pinned across midnight")
        selection.goToToday()
        expect(selection.dayID(today: tomorrow, calendar: calendar) == "2026-10-06", "Today follows midnight")
        selection.select(today, today: today, calendar: calendar)
        expect(selection.selectedID == nil, "Selecting today resumes following the current day")
        for (year, month, day, expectedHours, expectedID) in [(2026, 3, 28, 23.0, "2026-03-29"), (2026, 10, 24, 25.0, "2026-10-25")] {
            let origin = date(year, month, day, calendar: calendar)
            selection.goToToday()
            selection.move(by: 1, today: origin, calendar: calendar)
            expect(selection.dayID(today: origin, calendar: calendar) == expectedID, "Calendar navigation crosses DST correctly")
            expect(selection.date(today: origin, calendar: calendar).timeIntervalSince(origin) == expectedHours * 3600, "DST day is not hard-coded to 24 hours")
            selection.move(by: -1, today: origin, calendar: calendar)
            expect(selection.selectedID == nil, "DST reverse navigation returns to today")
        }
        for id in ["2026-02-30", "2025-02-29", "2026-13-01", "2026-00-10", "2026-10-00", "2026-1-05", "garbage"] {
            expect(!TaskDay.isValid(id), "Reject invalid civil date \(id)")
        }
        expect(TaskDay.isValid("2024-02-29"), "Valid leap day")
        selection.select(date(2031, 7, 18, calendar: calendar), today: today, calendar: calendar)
        var tokyo = calendar
        guard let japan = TimeZone(identifier: "Asia/Tokyo") else { fatalError("Missing timezone") }
        tokyo.timeZone = japan
        expect(TaskDay.id(for: selection.date(today: today, calendar: tokyo), calendar: tokyo) == "2031-07-18", "Selected civil date survives timezone changes")

        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let october = TaskMonthGrid(month: today, calendar: mondayCalendar)
        expect(october.weekdays.first == mondayCalendar.shortStandaloneWeekdaySymbols[1], "Week headings begin on the configured first weekday")
        expect(october.days.count == 42 && Set(october.days.map { TaskDay.id(for: $0, calendar: calendar) }).count == 42, "Calendar has six distinct full weeks")
        expect(TaskDay.id(for: october.days[0], calendar: calendar) == "2026-09-28", "October grid aligns Monday before the first")
        expect(TaskDay.id(for: october.days[3], calendar: calendar) == "2026-10-01", "October first falls under Thursday")
        expect(october.days.filter { october.contains($0) }.count == 31, "October shows every day once")
        let leap = TaskMonthGrid(month: date(2024, 2, 15, calendar: calendar), calendar: mondayCalendar)
        expect(leap.days.filter { leap.contains($0) }.count == 29, "Calendar includes February leap day")
        expect(TaskDay.id(for: leap.moving(by: 1), calendar: calendar) == "2024-03-01", "Changing month starts at first day without skipping a shorter month")
        let december = TaskMonthGrid(month: date(2026, 12, 31, calendar: calendar), calendar: mondayCalendar)
        expect(TaskDay.id(for: december.moving(by: 1), calendar: calendar) == "2027-01-01", "Month navigation crosses into next year")
        expect(TaskDay.id(for: december.moving(by: -1), calendar: calendar) == "2026-11-01", "Month navigation does not overflow from the 31st")
        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        let sundayGrid = TaskMonthGrid(month: today, calendar: sundayCalendar)
        expect(TaskDay.id(for: sundayGrid.days[0], calendar: calendar) == "2026-09-27", "Sunday-first locale aligns the grid correctly")
        let dstGrid = TaskMonthGrid(month: date(2026, 3, 15, calendar: calendar), calendar: mondayCalendar)
        expect(dstGrid.days.map { TaskDay.id(for: $0, calendar: calendar) }.contains("2026-03-29"), "Grid includes the DST transition date")
        expect(dstGrid.days.filter { dstGrid.contains($0) }.count == 31, "DST does not duplicate or omit a calendar day")

        let suite = "keep.tests.tasks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Preferences") }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TaskPersistence(defaults: defaults)
        let store = DailyTaskStore(persistence: persistence, calendar: calendar)
        expect(store.archive.days.isEmpty && store.tasks(on: "2026-10-05").isEmpty, "Fresh app has no sample tasks or fake history")
        expect(!store.add("  \n ", on: "2026-10-05"), "Ignore blank task")
        expect(!store.add("Invalid day", on: "2026-02-30"), "Reject invalid task date")
        expect(store.add("  Read a chapter  ", on: "2026-10-05"), "Add today's task")
        expect(store.tasks(on: "2026-10-05")[0].title == "Read a chapter", "Trim task input")
        expect(store.add("Earlier plan", on: "2026-10-04"), "Add to a past day")
        expect(store.add("Prepare presentation", on: "2026-10-06"), "Plan a future day")
        let task = store.tasks(on: "2026-10-05")[0]
        store.setComplete(true, taskID: task.id, on: "2026-10-05")
        expect(store.tasks(on: "2026-10-05")[0].isComplete, "Complete task on its own day")
        expect(!store.tasks(on: "2026-10-06")[0].isComplete, "Future completion remains independent")
        store.setComplete(true, taskID: task.id, on: "2026-10-06")
        expect(!store.tasks(on: "2026-10-06")[0].isComplete, "Wrong-day stale action cannot affect another task")
        let loaded = DailyTaskStore(persistence: persistence, calendar: calendar)
        expect(loaded.archive == store.archive, "Reload all days, UUIDs and completion states")
        expect(loaded.tasks(on: "2026-10-05")[0].id == task.id, "UUID remains stable across decoding")
        let shared = store
        shared.add("Second intention", on: "2026-10-05")
        expect(store.tasks(on: "2026-10-05").count == 2, "App-shared reference exposes tasks to every window")
        let before = store.archive
        store.remove(taskID: UUID(), on: "2026-10-05")
        expect(store.archive == before, "Unknown delete is harmless")
        store.remove(taskID: task.id, on: "2026-10-05")
        expect(store.tasks(on: "2026-10-05").map(\.title) == ["Second intention"], "Delete task by ID")
        expect(store.tasks(on: "2026-10-04").count == 1 && store.tasks(on: "2026-10-06").count == 1, "Delete preserves other dates")
        let last = store.tasks(on: "2026-10-05")[0]
        store.remove(taskID: last.id, on: "2026-10-05")
        expect(store.archive.days["2026-10-05"] == nil, "Delete final task leaves an empty day")
        expect(try persistence.load() == store.archive, "Deletions save immediately")

        for archive in [
            TaskArchive(days: ["2026-02-30": [task]]),
            TaskArchive(days: ["2026-10-05": [task, task]]),
            TaskArchive(days: ["2026-10-05": [FocusTask(title: " ")]])
        ] {
            defaults.set(try JSONEncoder().encode(archive), forKey: persistence.key)
            let blocked = DailyTaskStore(persistence: persistence)
            let corrupt = defaults.data(forKey: persistence.key)
            expect(blocked.loadFailed && !blocked.canEdit && blocked.persistenceError != nil, "Invalid saved tasks block edits")
            expect(!blocked.add("Don't overwrite", on: "2026-10-05"), "Blocked add cannot overwrite corruption")
            blocked.remove(taskID: task.id, on: "2026-10-05")
            blocked.setComplete(false, taskID: task.id, on: "2026-10-05")
            expect(defaults.data(forKey: persistence.key) == corrupt, "All blocked actions preserve original data")
            try persistence.save(TaskArchive(days: ["2026-10-06": [task]]))
            blocked.retryPersistence()
            expect(blocked.canEdit && blocked.persistenceError == nil && blocked.tasks(on: "2026-10-06") == [task], "Retry loads recovered data")
        }
        defaults.set("wrong type", forKey: persistence.key)
        expect(DailyTaskStore(persistence: persistence).loadFailed, "Unexpected stored preference type is not treated as empty")
        defaults.set(Data("not JSON".utf8), forKey: persistence.key)
        expect(DailyTaskStore(persistence: persistence).loadFailed, "Malformed JSON is protected")

        let processSuite = "keep.tests.task-process.\(UUID().uuidString)"
        for mode in ["write", "read"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [mode, processSuite]
            try process.run(); process.waitUntilExit()
            expect(process.terminationStatus == 0, "Tasks survive \(mode) subprocess")
        }
        UserDefaults.standard.removePersistentDomain(forName: processSuite)
        print("Passed \(checks) daily-task checks")
    }

    @MainActor private static func persistenceProbe(mode: String, suite: String) throws {
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Preferences") }
        let persistence = TaskPersistence(defaults: defaults)
        if mode == "write" {
            defaults.removePersistentDomain(forName: suite)
            let store = DailyTaskStore(persistence: persistence)
            store.add("Past", on: "2026-10-04")
            store.add("Today", on: "2026-10-05")
            store.add("Future", on: "2026-10-06")
            let task = store.tasks(on: "2026-10-04")[0]
            store.setComplete(true, taskID: task.id, on: "2026-10-04")
            defaults.synchronize()
        } else {
            let loaded = try persistence.load()
            expect(loaded.days.count == 3, "Cross-process dated history")
            expect(loaded.days["2026-10-04"]?.first?.isComplete == true, "Cross-process completion")
            expect(loaded.days["2026-10-06"]?.first?.title == "Future", "Cross-process future plan")
        }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { fatalError("Date") }
        return date
    }
    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
