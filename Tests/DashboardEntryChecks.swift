import Foundation

@main enum DashboardEntryChecks {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
    static func rejects(_ message: String, _ action: () throws -> Void) { do { try action(); preconditionFailure(message) } catch { checks += 1 } }
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12)) else { throw CocoaError(.coderInvalidValue) }
        let clock = ContinuousClock.now, day = "2026-10-13"
        let habitStore = HabitStore(calendar: calendar)
        let habit = try habitStore.add(name: "Reading habit", icon: .book, startDay: day, endDay: nil, goal: .amount(target: 30, unit: .minutes))
        let task = FocusTask(title: "Read", estimateMinutes: 30)
        let tasks = DailyTaskStore(archive: TaskArchive(days: [day: [task]]), calendar: calendar, habits: habitStore)
        let preferences = AppPreferences()
        let workspace = WorkspaceModel(calendar: calendar, date: date, timerPreferences: preferences, tasks: tasks, habits: habitStore)
        defer { workspace.shutdown() }
        var cues: [TimerSound] = []; workspace.onTimerReminder = { cues.append($0) }
        expect(workspace.projects.contains(.habits), "Habits is available in a new or existing default catalog")
        workspace.selectProject(.defaults[0], at: clock, date: date)
        workspace.startTask(task, on: day, timers: .flow, at: clock, date: date)
        var draft = CalendarEntryDraft(projectID: FocusProject.defaults[1].id, task: "  Earlier work  ", date: date, startTime: "09:00", endTime: "09:30")
        let entry = try workspace.addCalendarEntry(draft, at: clock + .seconds(10), now: date.addingTimeInterval(10))
        expect(entry.task == "Earlier work" && entry.source == .manual && entry.dayID == day, "Added entries retain trimmed names and distinguish manual source")
        expect(entry.timeZoneID == calendar.timeZone.identifier && close(entry.seconds, 1800), "Entered local times produce recorded seconds")
        expect(workspace.readIndex.sessions[entry.id]?.task == entry.task, "Calendar index receives added history")
        expect(workspace.selectedProject == .defaults[0] && workspace.taskReference == .task(id: task.id, dayID: day) && workspace.flow.phase(at: clock + .seconds(10)) == .running, "Entry creation settles but does not change running timer targets")
        workspace.stop(.flow, at: clock + .seconds(20), date: date.addingTimeInterval(20))
        let week = TimesheetWeek(containing: date, calendar: calendar)
        let projection = WeeklyProjection(days: week.dayIDs, index: workspace.readIndex)
        expect(close(projection.total, 1820) && close(projection.sessionTotal, 1820), "Timesheet and Calendar include the added duration and live recording exactly once")
        func stats() async throws -> StatsSnapshot {
            try await StatsCache().snapshot(batch: workspace.readIndex.batch(since: nil, epoch: nil), query: StatsQuery(),
                supplement: .init(taskRevision: 0, habitRevision: 0, tasks: [], habits: []), now: date.addingTimeInterval(100), calendar: calendar)
        }
        let addedStats = try await stats()
        expect(close(addedStats.total, 1820) && close(addedStats.focusActivity.seconds, 1820) && addedStats.pomodoros == 0, "Added work contributes to Stats and annual activity without inventing Pomodoro completions")
        expect(close(workspace.weeklyProjectSeconds(projectID: draft.projectID, today: date), 1800), "Added intervals contribute to project targets")
        draft.projectID = FocusProject.unassigned.id; draft.task = "Read"; draft.startTime = "08:00"; draft.endTime = "08:15"
        let unlinked = try workspace.addCalendarEntry(draft, at: clock + .seconds(20), now: date)
        expect(unlinked.project == .unassigned && unlinked.taskReference == nil, "No project and typed names remain explicit unlinked work")
        expect(close(workspace.readIndex.focusedSeconds(.task(id: task.id, dayID: day), on: day), 20), "Duplicate typed titles do not invent task identity")
        draft.reference = .task(id: task.id, dayID: day); draft.startTime = "07:00"; draft.endTime = "07:30"
        let linked = try workspace.addCalendarEntry(draft, at: clock + .seconds(20), now: date)
        expect(linked.taskReference == draft.reference && close(workspace.readIndex.focusedSeconds(draft.reference ?? .habit(id: UUID()), on: day), 1820), "Explicit task selection credits its actual time")
        let capture = SnapshotCapture(workspace: workspace, tasks: tasks, habits: habitStore, preferences: preferences)
        let snapshot = try capture.capture(.stats, at: clock + .seconds(20), date: date)
        let csv = try ExportReports.make(.init(data: .calendar, from: date, through: date, projectID: nil, taskKeys: nil), snapshot: snapshot)[0]
        expect(String(decoding: csv.contents, as: UTF8.self).contains(",manual,"), "Calendar exports identify added entries")
        let restored = try BackupEnvelope.decode(JSONEncoder().encode(BackupEnvelope(snapshot: BackupPayload(workspace: snapshot.workspace, tasks: tasks.archive, habits: habitStore.archive, settings: PortableSettings(preferences.snapshot)), deviceID: UUID(), date: date, appVersion: "test"))).validatedPayload()
        expect(restored.workspace.sessions.contains { $0.id == linked.id && $0.source == .manual && $0.taskReference == linked.taskReference }, "Added work and explicit identity survive backup round trip")
        let originalCount = workspace.ledger.sessions.count
        var invalid = draft; invalid.projectID = "invented"
        rejects("Unknown project must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        invalid = draft; invalid.reference = .task(id: UUID(), dayID: day)
        rejects("Missing task must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        invalid = draft; invalid.endTime = "06:00"
        rejects("End before start must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        invalid = draft; invalid.startTime = "24:00"
        rejects("24:00 start must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        invalid = draft; invalid.endTime = "25:00"
        rejects("Malformed time must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        invalid = draft; invalid.endTime = "13:00"
        rejects("Unfinished work must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        invalid = draft; invalid.task = String(repeating: "x", count: 201)
        rejects("Long title must be rejected") { try workspace.addCalendarEntry(invalid, at: clock + .seconds(20), now: date) }
        expect(workspace.ledger.sessions.count == originalCount, "Rejected drafts create no partial entries")
        draft.reference = nil; draft.task = ""; draft.date = date.addingTimeInterval(-86400); draft.startTime = "23:00"; draft.endTime = "24:00"
        let midnight = try workspace.addCalendarEntry(draft, at: clock + .seconds(20), now: date)
        expect(midnight.endMinute == 1440 && close(midnight.seconds, 3600) && midnight.task.isEmpty, "Past midnight endpoint and blank task names remain valid")
        workspace.startTask(FocusTask(id: habit.id, title: habit.name, habitID: habit.id), on: day, timers: .both, at: clock + .seconds(30), date: date.addingTimeInterval(30))
        expect(workspace.selectedProject?.id == FocusProject.habits.id && workspace.activeTaskName == habit.name, "Launching a habit atomically assigns Habits and its name")
        workspace.synchronize(at: clock + .seconds(40), date: date.addingTimeInterval(40))
        let timedHabit = workspace.ledger.sessions.last
        expect(timedHabit?.project.id == FocusProject.habits.id && timedHabit?.taskReference == .habit(id: habit.id) && timedHabit?.source == .flow, "Habit timer records under Habits with existing Flow priority")
        draft.projectID = FocusProject.habits.id; draft.task = habit.name; draft.date = date; draft.startTime = "06:00"; draft.endTime = "06:45"; draft.reference = .habit(id: habit.id)
        let habitEntry = try workspace.addCalendarEntry(draft, at: clock + .seconds(40), now: date.addingTimeInterval(40))
        expect(habitStore.isComplete(habit, on: day) && close(workspace.readIndex.focusedSeconds(.habit(id: habit.id), on: day), 2710), "Linked added work contributes to combined habit progress without capping")
        expect(cues.isEmpty && habitStore.archive.logs.isEmpty, "Adding historical habit work is silent and does not duplicate manual habit logs")
        try workspace.deleteSession(id: habitEntry.id, at: clock + .seconds(40), date: date.addingTimeInterval(40))
        expect(!habitStore.isComplete(habit, on: day), "Deleting an added entry updates habit progress")
        workspace.stopBothTimers(at: clock + .seconds(40), date: date.addingTimeInterval(40))
        workspace.removeTimesheetProject(.unassigned, dayIDs: [day], at: clock + .seconds(40), date: date)
        expect(!workspace.ledger.sessions.contains { $0.id == linked.id }, "Timesheet removal removes added session history")
        workspace.undoTimesheetRemoval(at: clock + .seconds(40), date: date)
        expect(workspace.ledger.sessions.contains { $0.id == linked.id && $0.taskReference == linked.taskReference }, "Undo restores added entries and attribution")
        workspace.deleteProject(.habits, at: clock + .seconds(40), date: date)
        workspace.startTask(FocusTask(id: habit.id, title: habit.name, habitID: habit.id), on: day, timers: .flow, at: clock + .seconds(50), date: date)
        expect(workspace.selectedProject?.id == FocusProject.habits.id && workspace.projects.contains(.habits), "Habit timing reactivates the default project if removed")
        workspace.stopBothTimers(at: clock + .seconds(50), date: date)
        let recent = workspace.taskSuggestions.first { $0.taskReference == .habit(id: habit.id) }
        if let recent { workspace.selectProject(.defaults[0], at: clock + .seconds(50), date: date); workspace.selectTask(recent, at: clock + .seconds(50), date: date) }
        expect(workspace.selectedProject?.id == FocusProject.habits.id && workspace.activeTaskName == habit.name, "Recent habit selection also restores the Habits target")
        var legacy = TimesheetLedger()
        let existing = FocusProject(id: UUID().uuidString, name: "Habits", accent: .sage, category: "Personal project")
        legacy.registerProject(existing)
        expect(legacy.catalogProjects.filter { $0.name == "Habits" }.count == 1 && legacy.ensureHabitsProject().id == existing.id, "Existing user Habits projects are reused without duplicates")
        try TimesheetPersistence.validate(workspace.ledger); try TimesheetPersistence.validate(legacy)
        checks += 2
        let suite = "keep.added-entry.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let persistent = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        defer { persistent.shutdown() }
        let persistedDraft = CalendarEntryDraft(task: "Persisted entry", date: date, startTime: "10:00", endTime: "10:15")
        let persisted = try persistent.addCalendarEntry(persistedDraft, at: clock, now: date)
        expect(try persistence.load().sessions.contains { $0.id == persisted.id && $0.source == .manual }, "Added entry is durable before publication")
        let reopened = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        defer { reopened.shutdown() }
        expect(reopened.readIndex.sessions[persisted.id]?.task == "Persisted entry", "Added work survives relaunch")
        let duplicate = FocusTask(title: task.title, estimateMinutes: 45)
        let searchTasks = DailyTaskStore(archive: TaskArchive(days: [day: [task, duplicate]]), calendar: calendar, habits: habitStore)
        let searchWorkspace = WorkspaceModel(ledger: workspace.ledger, calendar: calendar, date: date, tasks: searchTasks, habits: habitStore)
        defer { searchWorkspace.shutdown() }
        let options = searchWorkspace.entryTaskSuggestions(on: date, projectID: FocusProject.defaults[1].id)
        let readOptions = CalendarEntryTaskSuggestion.matching("  READ  ", in: options)
        expect(readOptions.filter { $0.title == "Read" }.count == 2, "Autocomplete keeps duplicate-title tasks as distinct explicit choices")
        expect(Set(readOptions.filter { $0.title == "Read" }.map(\.id)).count == 2, "Suggestion identities remain stable and unique")
        expect(readOptions.first?.title == "Read", "Exact matches rank before partial matches")
        expect(options.contains { $0.title == "Earlier work" && $0.reference == nil }, "Recorded manual names are available as unlinked recommendations")
        expect(CalendarEntryTaskSuggestion.matching("A completely new name", in: options).isEmpty, "Unknown names stay free-form instead of attaching to another task")
        expect(CalendarEntryTaskSuggestion.matching("", in: options).count == options.count, "Opening an empty search displays available recommendations")
        let accented = CalendarEntryTaskSuggestion(id: "accent", title: "Hören", detail: "Recent task", reference: nil)
        expect(CalendarEntryTaskSuggestion.matching("HOREN", in: [accented]).count == 1, "Autocomplete ignores case and diacritics")
        expect(!searchWorkspace.entryTaskSuggestions(on: date, projectID: FocusProject.unassigned.id).contains { $0.title == "Earlier work" }, "Recorded name suggestions follow the entry's selected project")
        var spring = draft; spring.reference = nil; spring.date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29)) ?? date; spring.startTime = "02:30"; spring.endTime = "03:30"
        rejects("Nonexistent DST times must be rejected") { _ = try spring.session(project: .unassigned, calendar: calendar, now: date) }
        print("Passed \(checks) added entry, attribution, Habits project, export and backup checks")
    }
}
