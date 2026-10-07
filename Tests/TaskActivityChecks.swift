import Foundation

@main enum TaskActivityChecks {
    private static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9)) ?? .now
        let instant = ContinuousClock.now
        func time(_ seconds: Int) -> ContinuousClock.Instant { instant.advanced(by: .seconds(seconds)) }
        func wall(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        let suite = "keep.activity-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, focusDuration: 100, date: date)
        workspace.setTaskName("Draft", at: instant, date: date)
        expect(workspace.taskSuggestions.isEmpty, "Idle input does not invent recent activity")
        workspace.startTask("  Read  ", timers: .both, at: instant, date: date)
        guard let keepRead = workspace.taskSuggestions.first else { preconditionFailure("No history") }
        expect(keepRead.title == "Read" && keepRead.project.id == "keep", "Starting a task stores trimmed title with the selected project")
        workspace.setTaskName("Write", at: time(3), date: wall(3))
        expect(workspace.taskSuggestions.map(\.title) == ["Write", "Read"], "Active edits remember recent tasks in order")
        workspace.toggleTaskPin(keepRead, at: time(3), date: wall(3))
        expect(workspace.taskSuggestions.first?.id == keepRead.id && workspace.taskSuggestions.first?.isPinned == true, "Pinned tasks appear before newer activity")
        expect(workspace.ledger.sessions.count == 1 && workspace.ledger.sessions[0].seconds == 3, "Pinning neither invents time nor changes recording context")
        workspace.selectProject(FocusProject.defaults[1], at: time(5), date: wall(5))
        workspace.startTask("Read", timers: .flow, at: time(6), date: wall(6))
        expect(workspace.taskSuggestions.filter { $0.title == "Read" }.count == 2, "The same task in different projects keeps distinct suggestions")
        workspace.selectTask(keepRead, at: time(9), date: wall(9))
        expect(workspace.selectedProject?.id == "keep" && workspace.taskName == "Read", "Selection restores task and project together")
        expect(workspace.flow.phase(at: time(9)) == .running && workspace.pomodoro.phase(at: time(9)) == .running, "Selection leaves both timers running")
        expect(workspace.ledger.sessions.last?.project.id == "german" && workspace.ledger.sessions.last?.task == "Read" && workspace.ledger.sessions.last?.seconds == 3, "Selection settles previous project/task before changing both")
        workspace.stop(.flow, at: time(12), date: wall(12))
        workspace.stop(.pomodoro, at: time(12), date: wall(12))
        expect(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } == 12, "Suggestion selection preserves single recording and overlap priority")
        workspace.selectTask(keepRead, at: time(13), date: wall(13))
        expect(workspace.flow.phase(at: time(13)) == .stopped && workspace.pomodoro.phase(at: time(13)) == .stopped, "Selecting while paused does not autoplay")
        workspace.startTask("read", timers: .flow, at: time(14), date: wall(14))
        workspace.stop(.flow, at: time(15), date: wall(15))
        expect(workspace.taskSuggestions.filter { $0.project.id == "keep" && $0.title.lowercased() == "read" }.count == 1, "Reuse deduplicates case-insensitive names within a project")
        expect(workspace.taskSuggestions.first?.id == keepRead.id && workspace.taskSuggestions.first?.isPinned == true, "Reuse preserves stable identity and pin")
        let restored = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        expect(restored.taskSuggestions.first?.id == keepRead.id && restored.taskSuggestions.first?.isPinned == true, "Task/project history and pins survive reload")
        expect(restored.taskName.isEmpty, "Suggestions do not restore the runtime current task")
        restored.toggleTaskPin(keepRead)
        expect(restored.taskSuggestions.first(where: { $0.id == keepRead.id })?.isPinned == false, "Tasks can be unpinned")
        restored.deleteProject(FocusProject.defaults[0])
        expect(restored.taskSuggestions.allSatisfy { $0.project.id != "keep" }, "Deleted projects no longer appear in suggestions")
        restored.selectTask(keepRead)
        expect(restored.selectedProject == nil && restored.taskName.isEmpty, "Stale selection cannot resurrect a deleted project")

        var archive = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace.ledger)) as? [String: Any] ?? [:]
        archive.removeValue(forKey: "taskActivities")
        defaults.set(try JSONSerialization.data(withJSONObject: archive), forKey: persistence.key)
        let migrated = try persistence.load()
        expect(!migrated.taskActivities.isEmpty && migrated.taskActivities.contains { $0.project.id == "german" && $0.title == "Read" }, "Legacy archives build suggestions from actual recorded sessions")
        let noTasks = WorkspaceModel(calendar: calendar, date: date)
        noTasks.play(.flow, at: instant, date: date)
        noTasks.stop(.flow, at: time(2), date: wall(2))
        expect(noTasks.taskSuggestions.isEmpty, "Unnamed sessions do not create empty suggestions")
        let resting = WorkspaceModel(calendar: calendar, focusDuration: 2, date: date)
        resting.play(.pomodoro, at: instant, date: date)
        resting.startBreak(at: time(2), date: wall(2))
        resting.setTaskName("Rest draft", at: time(3), date: wall(3))
        expect(resting.taskSuggestions.isEmpty, "Pomodoro breaks do not save work activity")
        let late = WorkspaceModel(calendar: calendar, focusDuration: 2, date: date)
        late.startTask("Focus", timers: .focus, at: instant, date: date)
        if let activity = late.taskSuggestions.first { late.toggleTaskPin(activity, at: time(5), date: wall(5)) }
        expect(late.ledger.sessions.map(\.seconds) == [2] && late.pomodoro.completedFocusIntervals == 1, "Pinning after late completion settles all focus time exactly once")
        archive["taskActivities"] = [["id": UUID().uuidString, "title": " ", "project": ["id": "keep", "name": "Keep", "accent": "terracotta", "category": "Personal project"], "lastUsed": 1, "isPinned": false]]
        let bad = try JSONSerialization.data(withJSONObject: archive)
        defaults.set(bad, forKey: persistence.key)
        let blocked = WorkspaceModel(persistence: persistence)
        expect(blocked.loadFailed, "Invalid saved activity blocks loading")
        blocked.startTask("New", timers: .both)
        blocked.toggleTaskPin(keepRead)
        expect(defaults.data(forKey: persistence.key) == bad, "Failed loads preserve saved history and block mutations")
        print("Passed \(checks) task activity checks")
    }
}
