import Foundation

@main enum WeeklyTargetsChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func rejects(_ action: () throws -> Void, _ message: String) {
        do { try action(); preconditionFailure(message) } catch { checks += 1 }
    }
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt; calendar.firstWeekday = 2
        func date(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
        }
        let now = date(8), clock = ContinuousClock.now
        expect(WeeklyTargets.parseHours("168") == 10080, "168 hour weekly limit")
        expect(WeeklyTargets.parseHours("1,5") == 90, "Decimal comma hours")
        expect(WeeklyTargets.parseHours("0.0167") == 1, "Round fractional hours to a minute")
        for input in ["0", "-1", "168.01", "NaN", "inf", "", "1x", "0.001"] {
            expect(WeeklyTargets.parseHours(input) == nil, "Reject invalid weekly hours")
        }
        for minutes in [1, 59, 60, 61, 10079, 10080] {
            expect(WeeklyTargets.parseHours(WeeklyTargets.hoursText(minutes)) == minutes, "Display round trips every minute without drift")
        }
        rejects({ _ = try WeeklyTargets.parse(goal: "2", minimum: "3", hours: true, maximum: 10080) }, "Minimum cannot exceed aspiration")
        rejects({ _ = try WeeklyTargets.parse(goal: "8", minimum: "1", hours: false, maximum: 7) }, "Check-ins capped at seven")
        expect(try WeeklyTargets.parse(goal: "168", minimum: "168", hours: true, maximum: 10080) == WeeklyTargets(goal: 10080, minimum: 10080), "Goal can equal minimum")

        let suite = "keep.weekly-targets.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspacePersistence = TimesheetPersistence(defaults: defaults)
        let workspace = WorkspaceModel(persistence: workspacePersistence, calendar: calendar, focusDuration: 60, date: now)
        let project = try workspace.createProject(name: "Practice", accent: .sage, at: clock, date: now)
        let targets = WeeklyTargets(goal: 600, minimum: 120)
        workspace.selectProject(project, at: clock, date: now)
        workspace.startBothTimers(at: clock, date: now)
        try workspace.updateProjectTargets(projectID: project.id, targets: targets, at: clock + .seconds(70), date: now.addingTimeInterval(70))
        expect(near(workspace.weeklyProjectSeconds(projectID: project.id, today: now.addingTimeInterval(70)), 70), "Changing targets settles concurrent timers once")
        expect(workspace.ledger.completedPomodoros.count == 1, "Changing targets preserves exactly-once Pomodoro completion")
        expect(try workspacePersistence.load().projectTargets[project.id] == targets, "Project targets persist independently of metadata")
        workspace.stopBothTimers(at: clock + .seconds(70), date: now.addingTimeInterval(70))
        workspace.edit(seconds: 50000, project: project, dayID: "2026-10-08", at: clock + .seconds(70), date: now.addingTimeInterval(70))
        expect(near(workspace.weeklyProjectSeconds(projectID: project.id, today: now.addingTimeInterval(70)), 70), "Manual total does not invent goal focus")
        rejects({ try workspace.updateProjectTargets(projectID: project.id, targets: .init(goal: 10081, minimum: 1)) }, "Reject over-limit project archive mutation")
        rejects({ try workspace.updateProjectTargets(projectID: "missing", targets: targets) }, "Reject stale deleted/missing project actions")
        expect(workspace.projectTargets[project.id] == targets, "Rejected changes preserve saved targets")
        if let session = workspace.ledger.sessions.first {
            try workspace.editSession(id: session.id, start: session.start, end: session.start.addingTimeInterval(30), at: clock + .seconds(70), date: now.addingTimeInterval(70))
            expect(near(workspace.weeklyProjectSeconds(projectID: project.id, today: now.addingTimeInterval(70)), 30), "Goal index patches edited session")
            workspace.removeTimesheetProject(project, dayIDs: [session.dayID], at: clock + .seconds(70), date: now.addingTimeInterval(70))
            expect(workspace.weeklyProjectSeconds(projectID: project.id, today: now.addingTimeInterval(70)) == 0, "Removal patches recorded goal index")
            workspace.undoTimesheetRemoval(at: clock + .seconds(70), date: now.addingTimeInterval(70))
            expect(near(workspace.weeklyProjectSeconds(projectID: project.id, today: now.addingTimeInterval(70)), 30), "Undo restores recorded goal index")
        }
        let reloaded = WorkspaceModel(persistence: workspacePersistence, calendar: calendar, date: now.addingTimeInterval(70))
        expect(reloaded.projectTargets[project.id] == targets && near(reloaded.weeklyProjectSeconds(projectID: project.id, today: now.addingTimeInterval(70)), 30), "Rebuild preserves goal definitions and derived time")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace.ledger)) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "projectTargets")
        let legacyLedger = try JSONDecoder().decode(TimesheetLedger.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(legacyLedger.projectTargets.isEmpty, "Legacy projects default to no targets")
        var invalidLedger = workspace.ledger
        invalidLedger.setProjectTargets(.init(goal: 5, minimum: 6), projectID: project.id)
        rejects({ try TimesheetPersistence.validate(invalidLedger) }, "Reject malformed project goals at import boundary")
        invalidLedger = workspace.ledger; invalidLedger.setProjectTargets(targets, projectID: "orphan")
        rejects({ try TimesheetPersistence.validate(invalidLedger) }, "Reject orphan goals at import boundary")

        let habits = HabitStore(persistence: HabitPersistence(defaults: defaults), calendar: calendar)
        let habit = try habits.add(name: "Read", icon: .book, startDay: "2026-10-01", endDay: nil,
            goal: .amount(target: 20, unit: .minutes), weeklyTargets: .init(goal: 180, minimum: 60))
        let tasks = DailyTaskStore(calendar: calendar, habits: habits)
        expect(habits.setAmount(30, habitID: habit.id, on: "2026-10-05", today: now), "Monday progress")
        expect(habits.setAmount(10, habitID: habit.id, on: "2026-10-08", today: now), "Partial progress")
        expect(habits.setAmount(200, habitID: habit.id, on: "2026-10-04", today: now), "Previous week progress")
        expect(habits.weeklyAmount(for: habit, today: now) == 40, "Weekly amounts include partial units, exclude previous week")
        try habits.update(habitID: habit.id, name: "Read daily", icon: .study, weekdays: [.tuesday, .friday], weeklyTargets: .init(goal: 10080, minimum: 60))
        guard let edited = habits.habits.first else { throw HabitError.missingHabit }
        expect(edited.id == habit.id && edited.goal == habit.goal && edited.startDay == habit.startDay, "Edit preserves identity, daily goal and dates")
        expect(edited.weekdays == [.tuesday, .friday] && edited.weeklyTargets?.goal == 10080, "Days and maximum time targets editable")
        expect(habits.archive.logs.count == 3 && habits.weeklyAmount(for: edited, today: now) == 40, "Schedule edits preserve recorded quantities")
        expect(habits.archive.isValid, "Recorded history stays valid after removing weekdays")
        expect(!habits.setAmount(20, habitID: habit.id, on: "2026-10-08", today: now), "New rest-day writes still rejected")
        expect(!tasks.tasks(on: "2026-10-08").contains { $0.habitID == habit.id }, "Shared Tasks reflects edited due days immediately")
        expect(tasks.tasks(on: "2026-10-09").contains { $0.habitID == habit.id }, "Newly scheduled day projects task")
        expect(habits.statistics(for: edited, month: now, today: now).monthlyCompletions == 0, "Consistency excludes logged days now marked rest")
        let before = habits.archive
        rejects({ try habits.update(habitID: habit.id, name: "Read", icon: .book, weekdays: [], weeklyTargets: nil) }, "Cannot remove every day")
        rejects({ try habits.update(habitID: habit.id, name: "Read", icon: .book, weekdays: [.monday, .monday], weeklyTargets: nil) }, "Cannot repeat days")
        rejects({ try habits.update(habitID: habit.id, name: "Read", icon: .book, weekdays: [.monday], weeklyTargets: .init(goal: 10081, minimum: 1)) }, "Reject over-168-hour habits")
        expect(habits.archive == before, "Rejected edits are atomic")
        let savedHabits = try HabitPersistence(defaults: defaults).load()
        expect(savedHabits == habits.archive, "Updated goals, days and retained logs round trip")
        var oldHabit = try JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any] ?? [:]
        oldHabit.removeValue(forKey: "weeklyTargets")
        expect(try JSONDecoder().decode(Habit.self, from: JSONSerialization.data(withJSONObject: oldHabit)).weeklyTargets == nil, "Legacy habit defaults no targets")
        let checkIn = try habits.add(name: "Walk", icon: .walk, startDay: "2026-10-01", endDay: nil, goal: .checkIn, weeklyTargets: .init(goal: 7, minimum: 2))
        expect(checkIn.weeklyTargets?.goal == 7, "Check-in targets use count units")
        rejects({ _ = try habits.add(name: "Invalid", icon: .walk, startDay: "2026-10-01", endDay: nil, goal: .checkIn, weeklyTargets: .init(goal: 8, minimum: 2)) }, "Check-in target weekly limit enforced")

        let payload = BackupPayload(workspace: workspace.ledger, tasks: tasks.archive, habits: habits.archive, settings: PortableSettings(SettingsArchive()))
        let envelope = try BackupEnvelope(snapshot: payload, deviceID: UUID(), date: now, appVersion: "test")
        let restored = try BackupEnvelope.decode(JSONEncoder().encode(envelope)).validatedPayload()
        expect(restored.workspace.projectTargets == workspace.projectTargets && restored.habits == habits.archive, "iCloud payload includes goals and updated schedules")

        var query = StatsQuery(); query.period = .year
        let empty = StatsInput(query: query, now: now, calendar: calendar, projects: [], sessions: [], completions: [], historyStartedAt: nil, entries: [], tasks: [], habits: [])
        let snapshot = try StatsSnapshot.make(empty)
        expect(snapshot.focusActivity.weeks.flatMap(\.days).filter(\.inYear).count == 365, "Annual grid contains each civil day once")
        let leapRange = StatsRange(start: date(1, month: 1, year: 2024, hour: 0), end: date(1, month: 1, year: 2025, hour: 0))
        let leap = FocusActivitySnapshot(range: leapRange, now: now, calendar: calendar)
        expect(leap.weeks.flatMap(\.days).filter(\.inYear).count == 366, "Leap day retained")
        expect(leap.weeks.allSatisfy { $0.days.count == 7 && calendar.component(.weekday, from: $0.days[0].date) == 2 }, "Monday-first full week columns")
        for (hours, level) in [(0.0, 0), (0.5, 1), (2, 2), (4, 3), (8, 4), (30, 4)] {
            expect(FocusActivitySnapshot.intensity(seconds: hours * 3600) == level, "Daily intensity represents actual hours")
        }
        query.period = .month
        let range = query.range(now: now, calendar: StatsSnapshot.calendar(calendar))
        let grid = FocusActivitySnapshot(range: range, now: now, calendar: calendar).filling(["2026-10-08": 3600, "2026-09-30": 80000, "2026-10-09": 90000])
        expect(grid.seconds == 3600, "Grid excludes unselected and future days")
        expect(grid.weeks.flatMap(\.days).first { $0.id == "2026-10-08" }?.seconds == 3600, "Correct day receives focus time")
        let cache = StatsCache(), supplement = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
        let cached = try await cache.snapshot(batch: workspace.readIndex.batch(since: nil, epoch: nil), query: query, supplement: supplement, now: now.addingTimeInterval(70), calendar: calendar)
        expect(near(cached.focusActivity.seconds, 30), "Cached grid uses real sessions, ignores adjusted totals")
        query.projectID = "missing"
        let filtered = try await cache.snapshot(batch: workspace.readIndex.batch(since: nil, epoch: nil), query: query, supplement: supplement, now: now.addingTimeInterval(70), calendar: calendar)
        expect(filtered.focusActivity.seconds == 0, "Grid honors project/task filters")
        workspace.shutdown(); reloaded.shutdown()
        print("Passed \(checks) weekly targets, schedule editing and focus activity checks")
    }
}
