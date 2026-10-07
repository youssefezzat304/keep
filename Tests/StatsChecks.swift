import Foundation

@main enum StatsChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.firstWeekday = 2
        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
        }
        let now = date(7, 10, 30)
        func session(_ project: String, _ task: String, _ day: Int, _ hour: Int, _ seconds: Double, month: Int = 10) -> StatsInput.Session {
            let start = date(day, hour, month: month)
            return .init(projectID: project, task: task, dayID: StatsSnapshot.dayID(start, calendar: calendar), start: start, end: start.addingTimeInterval(seconds), timeZoneID: calendar.timeZone.identifier)
        }
        let projects: [StatsInput.Project] = [.init(id: "a", name: "Alpha", accent: "sage", deleted: false), .init(id: "b", name: "Beta", accent: "terracotta", deleted: true), .init(id: "no-project", name: "No project", accent: "neutral", deleted: false)]
        let sessions = [session("a", "Hören", 5, 9, 3600), session("a", " hören ", 6, 9, 3600), session("b", "Hören", 7, 9, 3600), session("a", "", 7, 10, 1800), session("a", "Hören", 28, 9, 3600, month: 9), session("a", "Hören", 30, 9, 3600, month: 9), session("a", "Hören", 30, 12, 3600, month: 9)]
        func input(_ query: StatsQuery = StatsQuery(), records: [StatsInput.Session]? = nil, habits: [StatsInput.Habit] = [], tasks: [StatsInput.TaskDay] = [], current: Date? = nil, using sourceCalendar: Calendar? = nil) -> StatsInput {
            StatsInput(query: query, now: current ?? now, calendar: sourceCalendar ?? calendar, projects: projects, sessions: records ?? sessions,
                completions: [.init(projectID: "b", task: "Hören", dayID: "2026-10-07", date: date(7, 10))],
                historyStartedAt: date(1), entries: [.init(projectID: "a", dayID: "2026-10-05", seconds: 50000)], tasks: tasks, habits: habits)
        }
        let week = try StatsSnapshot.make(input())
        expect(week.buckets.count == 7 && week.buckets.first?.id == "2026-10-05", "Monday-first week with future zero buckets")
        expect(close(week.total, 12600) && week.activeDays == 3 && close(week.average, 4200), "Total, distinct active days, active-day denominator")
        expect(close(week.previousTotal, 7200), "Previous week excludes time after matching Wednesday cutoff")
        expect(close(week.buckets.reduce(0) { $0 + $1.seconds }, week.total), "Chart total reconciles")
        expect(close(week.hours.reduce(0, +), week.total) && close(week.weekdays.reduce(0, +), week.total), "Hourly and weekday distributions reconcile")
        expect(close(week.adjustedTotal, 50000) && week.pomodoros == 1, "Adjusted totals and completion events remain separate")
        expect(week.distribution.count == 2 && close(week.weeklyGoalSeconds, week.total), "All-project distribution and weekly goal")
        var query = StatsQuery(); query.projectID = "a"; query.taskKeys = [StatsQuery.taskKey("HOREN")]
        let task = try StatsSnapshot.make(input(query))
        expect(close(task.total, 7200) && task.pomodoros == 0, "Case/diacritic-insensitive task grouping remains project scoped")
        expect(task.distribution.count == 1 && close(task.weeklyGoalSeconds, week.total), "Goal ignores task/project filters")
        query.taskKeys = ["horen", ""]
        let multiple = try StatsSnapshot.make(input(query))
        expect(close(multiple.total, 9000) && multiple.distribution.count == 2, "Multiple task names combine without crossing projects")
        query.taskKeys = [""]
        expect(close(try StatsSnapshot.make(input(query)).total, 1800), "Explicit unnamed task selection")
        query.taskKeys = ["missing"]
        expect(try StatsSnapshot.make(input(query)).activeDays == 0, "Unknown retained task selection yields a real empty state")
        var custom = StatsQuery(); custom.period = .custom; custom.customStart = date(5); custom.customEnd = date(6)
        let twoDays = try StatsSnapshot.make(input(custom))
        expect(twoDays.buckets.count == 2 && close(twoDays.total, 7200), "Custom end date is inclusive")
        custom.customEnd = date(5)
        expect(try StatsSnapshot.make(input(custom)).buckets.count == 1, "Single-day custom range")
        custom.customStart = date(1, month: 9); custom.customEnd = date(7)
        expect(try StatsSnapshot.make(input(custom)).buckets.count < 10, "Longer custom ranges group weekly")
        custom.customStart = date(1, month: 1); custom.customEnd = date(7)
        expect(try StatsSnapshot.make(input(custom)).buckets.count == 10, "Custom ranges over 180 days group monthly")
        var year = StatsQuery(); year.period = .year
        expect(try StatsSnapshot.make(input(year)).buckets.count == 12, "Year keeps twelve months")
        var month = StatsQuery(); month.period = .month; month.anchor = date(1, month: 2, year: 2024)
        expect(try StatsSnapshot.make(input(month)).buckets.count == 29, "Leap February")
        expect(try StatsSnapshot.make(input(month)).pomodorosAvailable == false, "Pre-feature Pomodoro history is unavailable")
        var navigation = StatsQuery()
        navigation.move(1, now: now, calendar: calendar)
        expect(navigation.anchor == nil, "Cannot navigate into future weeks")
        navigation.move(-1, now: now, calendar: calendar)
        expect(navigation.range(now: now, calendar: calendar).start == date(28, month: 9), "Previous week navigation")
        let partialMonth = try StatsSnapshot.make(input(monthQuery(), records: [session("a", "", 28, 9, 3600, month: 2)], current: date(31, 10, month: 3)))
        expect(close(partialMonth.previousTotal, 3600), "Comparison clamps shorter previous month")
        let habitID = UUID()
        let habit = StatsInput.Habit(id: habitID, name: "Read", icon: "book.fill", start: "2026-10-01", end: nil, weekdays: [2, 4, 6], target: 10,
            progress: ["2026-10-02": 10, "2026-10-05": 10, "2026-10-07": 5])
        let habits = try StatsSnapshot.make(input(habits: [habit], tasks: [.init(dayID: "2026-10-05", total: 2, completed: 1), .init(dayID: "2026-10-08", total: 3, completed: 3)]))
        expect(habits.habitsDue == 2 && habits.habitsCompleted == 1, "Scheduled rates exclude rest/future days and partial goals")
        expect(habits.habits.first?.currentStreak == 2 && habits.habits.first?.bestStreak == 1, "Pending today preserves streak that began before range")
        expect(habits.tasksTotal == 2 && habits.tasksCompleted == 1, "Future assigned tasks excluded")
        custom.customStart = date(1); custom.customEnd = date(5)
        expect(try StatsSnapshot.make(input(custom, habits: [habit])).habits.first?.currentStreak == 2, "Past completed end preserves scheduled streak")
        custom.customEnd = date(7)
        expect(try StatsSnapshot.make(input(custom, habits: [habit], current: date(8))).habits.first?.currentStreak == 0, "Past incomplete due day is not treated as pending")
        let ended = StatsInput.Habit(id: habitID, name: "Read", icon: "book.fill", start: "2026-10-01", end: "2026-10-05", weekdays: [2, 4, 6], target: 10, progress: habit.progress)
        expect(try StatsSnapshot.make(input(habits: [ended])).habits.first?.currentStreak == 0, "Ended habit current streak remains zero")
        let streakRecords = [session("a", "", 5, 9, 60), session("a", "", 6, 9, 60)]
        expect(try StatsSnapshot.make(input(records: streakRecords)).currentStreak == 2, "Focus permits actual today pending")
        custom.customStart = date(5); custom.customEnd = date(7)
        expect(try StatsSnapshot.make(input(custom, records: streakRecords, current: date(8))).currentStreak == 0, "Past empty end breaks focus streak")
        // Repeated 02:00 hour contributes twice; nonexistent spring hour contributes zero.
        let autumnStart = date(25, 1)
        let autumnRecord = StatsInput.Session(projectID: "a", task: "", dayID: "2026-10-25", start: autumnStart, end: autumnStart.addingTimeInterval(4 * 3600), timeZoneID: calendar.timeZone.identifier)
        custom.customStart = date(25); custom.customEnd = date(25)
        let autumn = try StatsSnapshot.make(input(custom, records: [autumnRecord], current: date(26)))
        expect(close(autumn.total, 14400) && close(autumn.hours[2], 7200), "Repeated DST hour is counted twice without losing time")
        let springStart = date(29, 1, month: 3)
        let springRecord = StatsInput.Session(projectID: "a", task: "", dayID: "2026-03-29", start: springStart, end: springStart.addingTimeInterval(3 * 3600), timeZoneID: calendar.timeZone.identifier)
        custom.customStart = date(29, month: 3); custom.customEnd = custom.customStart
        let spring = try StatsSnapshot.make(input(custom, records: [springRecord]))
        expect(close(spring.hours[2], 0) && close(spring.hours.reduce(0, +), 10800), "Spring gap preserves elapsed time")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
        let traveling = session("a", "", 7, 0, 3600)
        let travel = try StatsSnapshot.make(input(records: [traveling], using: utc))
        expect(close(travel.total, 3600) && close(travel.hours[0], 3600), "Travel preserves saved civil day and recorded local hour")
        var unassigned = StatsQuery(); unassigned.projectID = "no-project"
        expect(close(try StatsSnapshot.make(input(unassigned, records: [session("no-project", "", 5, 9, 60)])).total, 60), "No project is an explicit filter")
        var deleted = StatsQuery(); deleted.projectID = "b"
        expect(close(try StatsSnapshot.make(input(deleted)).total, 3600), "Deleted project history remains queryable")
        let empty = try StatsSnapshot.make(input(records: []))
        expect(empty.total == 0 && empty.average == 0 && empty.distribution.isEmpty && empty.habitsDue == 0, "Zero denominators and empty archives")
        let canceledInput = input(year)
        let operation = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try StatsSnapshot.make(canceledInput)
        }
        operation.cancel()
        do { _ = try await operation.value; preconditionFailure("Canceled calculation must not publish") }
        catch is CancellationError { checks += 1 }
        print("Passed \(checks) Stats aggregation checks")
    }
    static func monthQuery() -> StatsQuery { var query = StatsQuery(); query.period = .month; return query }
}
