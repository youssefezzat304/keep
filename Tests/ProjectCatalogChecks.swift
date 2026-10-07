import Foundation

@main enum ProjectCatalogChecks {
    private static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    static func main() throws {
        let suite = "keep.project-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9)) ?? .now
        let instant = ContinuousClock.now
        func time(_ seconds: Int) -> ContinuousClock.Instant { instant.advanced(by: .seconds(seconds)) }
        func wall(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, focusDuration: 100, date: date)
        let project = try workspace.createProject(name: "  Study  ", accent: .sage, at: instant, date: date)
        expect(project.name == "Study" && workspace.projects.contains(project), "Creation trims and registers the project")
        expect(workspace.selectedProject == FocusProject.defaults.first && workspace.ledger.entries.isEmpty, "Creation alone changes neither selection nor recorded time")
        expect(tryLoad(persistence).customProjects.contains(project), "An unused project persists")
        do {
            _ = try workspace.createProject(name: "study", accent: .sage, at: instant, date: date)
            preconditionFailure("Duplicate accepted")
        } catch ProjectCreationError.duplicateName { checks += 1 }
        workspace.selectProject(project, at: instant, date: date)
        workspace.startTask("Read", timers: .both, at: instant, date: date)
        workspace.deleteProject(project, at: time(10), date: wall(10))
        expect(!workspace.projects.contains(project) && workspace.selectedProject == nil, "Active deletion removes the project and selects No project")
        expect(workspace.pomodoro.phase(at: time(10)) == .running && workspace.flow.phase(at: time(10)) == .running && workspace.taskName == "Read", "Deletion preserves independent timers and task")
        expect(workspace.ledger.sessions.first?.project == project && workspace.ledger.sessions.first?.seconds == 10, "Deletion settles elapsed time under the removed project")
        workspace.stop(.flow, at: time(15), date: wall(15))
        workspace.stop(.pomodoro, at: time(15), date: wall(15))
        expect(workspace.ledger.sessions.map(\.seconds) == [10, 5], "Overlap counts once across the project boundary")
        expect(workspace.ledger.sessions.last?.project == .unassigned, "Future time is recorded unassigned")
        workspace.selectProject(project, at: time(15), date: wall(15))
        expect(workspace.selectedProject == nil, "A stale picker cannot reselect a deleted project")
        let restored = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        expect(!restored.projects.contains(project) && restored.ledger.sessions.map(\.project) == workspace.ledger.sessions.map(\.project) && restored.ledger.sessions.map(\.seconds) == [10, 5], "Reload keeps deletion and historical project metadata/duration")
        let replacement = try workspace.createProject(name: "Study", accent: .sage, at: time(15), date: wall(15))
        expect(replacement.id != project.id && workspace.projects.contains(replacement), "A reused name gets a new identity")
        let dayID = TimesheetWeek.dayID(for: date, calendar: calendar)
        workspace.removeTimesheetProject(project, dayIDs: [dayID], at: time(15), date: wall(15))
        workspace.undoTimesheetRemoval(at: time(15), date: wall(15))
        expect(!workspace.projects.contains(project) && workspace.ledger.sessions.contains(where: { $0.project == project && $0.seconds == 10 }), "Timesheet Undo restores history without resurrecting the catalog project")
        for builtIn in FocusProject.defaults { workspace.deleteProject(builtIn, at: time(15), date: wall(15)) }
        workspace.deleteProject(replacement, at: time(15), date: wall(15))
        let empty = WorkspaceModel(persistence: persistence, calendar: calendar, date: date)
        expect(empty.projects.isEmpty && empty.selectedProject == nil, "Deleting every project survives reload without reseeding defaults")
        let saved = defaults.data(forKey: persistence.key)
        empty.deleteProject(.unassigned)
        empty.deleteProject(project)
        expect(defaults.data(forKey: persistence.key) == saved, "Unknown and repeated deletions are harmless")

        let focus = WorkspaceModel(calendar: calendar, focusDuration: 100, date: date)
        focus.play(.pomodoro, at: instant, date: date)
        focus.deleteProject(FocusProject.defaults[1], at: time(3), date: wall(3))
        focus.deleteProject(FocusProject.defaults[0], at: time(5), date: wall(5))
        focus.stop(.pomodoro, at: time(8), date: wall(8))
        expect(focus.ledger.sessions.map(\.seconds) == [5, 3], "Inactive deletion leaves the session intact; active focus deletion splits it")
        expect(focus.pomodoro.phase(at: time(8)) == .stopped, "Focus remains controllable after deletion")
        let rest = WorkspaceModel(calendar: calendar, focusDuration: 5, date: date)
        rest.play(.pomodoro, at: instant, date: date)
        rest.startBreak(at: time(5), date: wall(5))
        rest.deleteProject(FocusProject.defaults[0], at: time(6), date: wall(6))
        rest.synchronize(at: time(8), date: wall(8))
        expect(rest.ledger.sessions.map(\.seconds) == [5] && rest.pomodoro.interval == .rest && rest.pomodoro.phase(at: time(8)) == .running, "Deleting during a break preserves the break and excludes its time")

        let paused = WorkspaceModel(calendar: calendar, date: date)
        paused.play(.flow, at: instant, date: date)
        paused.stop(.flow, at: time(3), date: wall(3))
        paused.deleteProject(FocusProject.defaults[0], at: time(5), date: wall(5))
        expect(paused.flow.phase(at: time(5)) == .stopped && paused.selectedProject == nil, "Deleting a paused project does not resume its timer")
        paused.play(.flow, at: time(8), date: wall(8))
        paused.stop(.flow, at: time(10), date: wall(10))
        expect(paused.ledger.sessions.map(\.seconds) == [3, 2] && paused.ledger.sessions.last?.project == .unassigned, "Resume records only future unassigned time and excludes the pause")

        defaults.set(Data("{\"entries\":[]}".utf8), forKey: persistence.key)
        expect(tryLoad(persistence).deletedProjectIDs.isEmpty, "Legacy archives need no deleted-ID field")
        let legacy = WorkspaceModel(persistence: persistence)
        expect(legacy.projects == FocusProject.defaults, "Legacy catalogs retain their defaults")
        for invalidID in ["unknown", FocusProject.unassigned.id] {
            let data = try JSONSerialization.data(withJSONObject: ["entries": [], "deletedProjectIDs": [invalidID]])
            defaults.set(data, forKey: persistence.key)
            let blocked = WorkspaceModel(persistence: persistence)
            expect(blocked.loadFailed, "Invalid deleted IDs block loading")
            blocked.deleteProject(FocusProject.defaults[0])
            do { _ = try blocked.createProject(name: "New", accent: .sage); preconditionFailure("Invalid archive overwritten") }
            catch ProjectCreationError.unavailable { checks += 1 }
            expect(defaults.data(forKey: persistence.key) == data, "Failed loads preserve saved bytes")
        }
        print("Passed \(checks) project catalog checks")
    }

    private static func tryLoad(_ persistence: TimesheetPersistence) -> TimesheetLedger {
        do { return try persistence.load() }
        catch { preconditionFailure("Expected valid archive: \(error)") }
    }
}
