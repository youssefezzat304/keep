import Foundation

@main enum ProjectEditingChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }

    static func main() async throws {
        let suite = "keep.project-editing.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9)) ?? .distantPast
        let instant = ContinuousClock.now
        func time(_ seconds: Int) -> ContinuousClock.Instant { instant.advanced(by: .seconds(seconds)) }
        func wall(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, focusDuration: 10, date: date)
        let original = FocusProject.defaults[0]
        let custom = try workspace.createProject(name: "Study", accent: .sage, at: instant, date: date)
        workspace.startTask("Read", timers: .both, at: instant, date: date)
        workspace.synchronize(at: time(5), date: wall(5))
        let session = workspace.ledger.sessions[0]
        let week = TimesheetWeek(containing: date, calendar: calendar)
        let dashboard = DashboardQueryModel()
        dashboard.refresh(week: week, index: workspace.readIndex, calendar: calendar)
        let beforeRevision = workspace.readIndex.catalogRevision
        let cache = StatsCache()
        let supplement = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
        let batch = workspace.readIndex.batch(since: nil, epoch: nil)
        _ = try await cache.snapshot(batch: batch, query: StatsQuery(), supplement: supplement, now: wall(5), calendar: calendar)
        try workspace.updateProject(original, name: "  My focus  ", accent: .sage, at: time(10), date: wall(10))
        guard let edited = workspace.projects.first(where: { $0.id == original.id }) else { preconditionFailure("Missing edited project") }
        expect(edited.name == "My focus" && edited.accent == .sage && edited.category == original.category, "Trimmed edits preserve identity/category and allow a used color")
        expect(workspace.selectedProject == edited && workspace.taskName == "Read", "Active target reflects the edit without changing its task")
        expect(workspace.flow.phase(at: time(10)) == .running && workspace.pomodoro.phase(at: time(10)) == .completed, "Running Flow and completed Pomodoro retain their phases")
        expect(workspace.ledger.sessions[0].id == session.id && workspace.ledger.sessions[0].project == edited && workspace.ledger.sessions[0].seconds == 10, "Settled session retains identity/duration and gets edited display metadata")
        let completion = workspace.ledger.completedPomodoros[0]
        expect(completion.project == original && completion.task == "Read" && completion.completedAt == wall(10), "Completion at edit boundary captures its original finishing snapshot")
        expect(workspace.taskSuggestions.first?.project == edited, "Task suggestions refresh metadata")
        expect(workspace.readIndex.catalogRevision > beforeRevision, "Project metadata invalidates cached queries")
        dashboard.refresh(week: week, index: workspace.readIndex, calendar: calendar)
        expect(dashboard.projection.projects.contains(edited) && dashboard.projection.total == 10, "Warm weekly projection refreshes metadata and settled totals")
        let snapshot = try await cache.snapshot(batch: workspace.readIndex.batch(since: batch.revision, epoch: batch.epoch), query: StatsQuery(), supplement: supplement, now: wall(10), calendar: calendar)
        expect(snapshot.total == 10 && snapshot.pomodoros == 1 && snapshot.distribution.first?.name == edited.name, "Warm Stats refreshes names and retains time/completion count")
        let loaded = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        expect(loaded.projects.contains(edited) && loaded.selectedProject == edited && loaded.ledger.projectOverrides == [edited], "Built-in edits save immediately and survive relaunch")
        expect(loaded.ledger.completedPomodoros[0].project == original, "Relaunch preserves completion-time snapshot")
        workspace.stop(.flow, at: time(15), date: wall(15))
        expect(workspace.ledger.sessions.map(\.seconds) == [10, 5] && workspace.ledger.sessions.allSatisfy { $0.project == edited }, "Live recording after an edit continues without loss or double counting")
        workspace.selectProject(original, at: time(15), date: wall(15))
        expect(workspace.selectedProject == edited, "A stale picker resolves current project metadata")
        let day = week.dayIDs[2]
        workspace.removeTimesheetProject(edited, dayIDs: [day], at: time(15), date: wall(15))
        try workspace.updateProject(edited, name: "Renamed again", accent: .denim, at: time(15), date: wall(15))
        let renamed = workspace.selectedProject
        expect(workspace.lastTimesheetRemoval?.project == renamed, "Pending Undo notice uses the edited name")
        workspace.undoTimesheetRemoval(at: time(15), date: wall(15))
        expect(workspace.ledger.sessions.allSatisfy { $0.project == renamed } && workspace.ledger.total(dayIDs: [day]) == 15, "Undo restores current metadata without changing time")
        workspace.edit(seconds: 20, project: original, dayID: day, at: time(15), date: wall(15))
        expect(workspace.ledger.entries.first?.project == renamed, "Stale Timesheet editors cannot revert project metadata")
        try workspace.updateProject(custom, name: "Research", accent: .butter, at: time(15), date: wall(15))
        expect(try persistence.load().customProjects.first?.name == "Research", "Custom project edits persist")
        for (name, accent, expected) in [("", FocusProject.Accent.sage, ProjectCreationError.invalidName), (String(repeating: "a", count: 81), .sage, .invalidName), ("research", .sage, .duplicateName), ("No project", .sage, .duplicateName), ("Valid", .neutral, .invalidColor)] {
            let bytes = defaults.data(forKey: persistence.key)
            do { try workspace.updateProject(original, name: name, accent: accent, at: time(15), date: wall(15)); preconditionFailure("Invalid edit accepted") }
            catch let error as ProjectCreationError { expect(String(describing: error) == String(describing: expected), "Invalid edit reports correct error") }
            expect(defaults.data(forKey: persistence.key) == bytes, "Invalid edit leaves archive untouched")
        }
        guard let latest = renamed else { preconditionFailure("Missing target") }
        workspace.deleteProject(latest, at: time(15), date: wall(15))
        expect(workspace.readIndex.statsProjects.contains { $0.id == latest.id && $0.name == latest.name && $0.deleted }, "Deleted history keeps latest catalog display metadata")
        do { try workspace.updateProject(latest, name: "Gone", accent: .sage); preconditionFailure("Deleted project edited") }
        catch ProjectCreationError.missing { checks += 1 }
        let deleted = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        expect(!deleted.projects.contains(latest) && deleted.selectedProject == nil, "Deleted built-in override is not resurrected on reload")
        defaults.set(Data("{\"entries\":[]}".utf8), forKey: persistence.key)
        expect(try persistence.load().projectOverrides.isEmpty, "Legacy archives need no override field")
        let valid = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace.ledger)) as? [String: Any] ?? [:]
        for overrides in [ [["id": "unknown", "name": "Invalid", "accent": "sage", "category": "Test"]], [["id": "keep", "name": "", "accent": "sage", "category": "Test"]], [["id": "keep", "name": "One", "accent": "sage", "category": "Test"], ["id": "keep", "name": "Two", "accent": "sage", "category": "Test"]] ] {
            var archive = valid; archive["projectOverrides"] = overrides
            let bytes = try JSONSerialization.data(withJSONObject: archive); defaults.set(bytes, forKey: persistence.key)
            let blocked = WorkspaceModel(persistence: persistence)
            expect(blocked.loadFailed, "Invalid built-in overrides block loading")
            do { try blocked.updateProject(original, name: "Change", accent: .sage); preconditionFailure("Corrupt archive changed") }
            catch ProjectCreationError.unavailable { checks += 1 }
            expect(defaults.data(forKey: persistence.key) == bytes, "Failed load preserves bytes")
        }
        print("Passed \(checks) project editing checks")
    }
}
