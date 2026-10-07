import Foundation

@main enum PomodoroCompletionChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        let origin = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 23, minute: 59, second: 55)) ?? .now
        let instant = ContinuousClock.now
        func tick(_ value: Int) -> ContinuousClock.Instant { instant.advanced(by: .seconds(value)) }
        func date(_ value: Int) -> Date { origin.addingTimeInterval(Double(value)) }
        let suite = "keep.completion-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Test preferences unavailable") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, focusDuration: 10, date: origin)
        workspace.setTaskName("First", at: tick(0), date: date(0))
        workspace.play(.pomodoro, at: tick(0), date: date(0))
        workspace.setTaskName("Second", at: tick(4), date: date(4))
        workspace.selectProject(FocusProject.defaults[1], at: tick(6), date: date(6))
        workspace.setTaskName("After completion", at: tick(12), date: date(12))
        let event = workspace.ledger.completedPomodoros.first
        expect(event?.task == "Second" && event?.project.id == "german", "Count belongs to finishing target, before delayed action")
        expect(event?.completedAt == date(10) && event?.dayID == "2026-10-08", "Delayed completion maps actual boundary across midnight")
        expect(event?.focusDuration == 10 && workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } == 10, "Completion duration and recording stay independent")
        workspace.synchronize(at: tick(14), date: date(14))
        expect(workspace.ledger.completedPomodoros.count == 1, "Repeated synchronization cannot duplicate completion")
        expect(try persistence.load().completedPomodoros.count == 1, "Completion immediately persists")
        workspace.startBothTimers(at: tick(14), date: date(14))
        workspace.stop(.pomodoro, at: tick(17), date: date(17))
        workspace.play(.pomodoro, at: tick(20), date: date(20))
        workspace.synchronize(at: tick(30), date: date(30))
        expect(workspace.ledger.completedPomodoros.count == 2 && workspace.ledger.completedPomodoros.last?.completedAt == date(27), "Pause excludes gaps and concurrent Flow doesn't suppress completion")
        expect(workspace.ledger.completedPomodoros.first?.id != workspace.ledger.completedPomodoros.last?.id, "New focus interval has unique identity")
        workspace.startBreak(at: tick(30), date: date(30))
        workspace.synchronize(at: tick(400), date: date(400))
        expect(workspace.ledger.completedPomodoros.count == 2, "Break completion never counts")
        workspace.play(.pomodoro, at: tick(400), date: date(400))
        workspace.reset(.pomodoro, at: tick(403), date: date(403))
        expect(workspace.ledger.completedPomodoros.count == 2, "Abandoned partial focus never counts")
        workspace.play(.pomodoro, at: tick(403), date: date(403))
        workspace.selectProject(nil, at: tick(413), date: date(413))
        expect(workspace.ledger.completedPomodoros.last?.project.id == "german", "Exact-boundary target change settles completion first")
        workspace.play(.pomodoro, at: tick(414), date: date(414))
        workspace.synchronize(at: tick(1000), date: date(1000))
        expect(workspace.ledger.completedPomodoros.count == 4 && workspace.ledger.completedPomodoros.last?.project.id == "no-project", "Sleep/delayed updates count once under unassigned target")
        if let first = workspace.ledger.sessions.first {
            try workspace.deleteSession(id: first.id, at: tick(1000), date: date(1000))
        }
        expect(workspace.ledger.completedPomodoros.count == 4, "Calendar deletion does not rewrite actual completion history")
        let loaded = WorkspaceModel(persistence: persistence, calendar: calendar, date: date(1001))
        expect(loaded.ledger.completedPomodoros.count == 4 && loaded.pomodoro.phase() == .idle, "Completion history survives reload without runtime restoration")
        var archived = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace.ledger)) as? [String: Any] ?? [:]
        archived.removeValue(forKey: "completedPomodoros"); archived.removeValue(forKey: "pomodoroHistoryStartedAt")
        defaults.set(try JSONSerialization.data(withJSONObject: archived), forKey: persistence.key)
        let legacy = WorkspaceModel(persistence: persistence, calendar: calendar, date: date(1002))
        expect(!legacy.loadFailed && legacy.ledger.completedPomodoros.isEmpty && legacy.ledger.pomodoroHistoryStartedAt == date(1002), "Legacy archive begins coverage without estimating counts")
        var corrupt = workspace.ledger
        corrupt.recordCompletion(CompletedPomodoro(id: UUID(), project: .unassigned, task: "", completedAt: date(1), dayID: "wrong", timeZoneID: "invalid", focusDuration: -1))
        try persistence.save(corrupt)
        let savedBytes = defaults.data(forKey: persistence.key)
        let protected = WorkspaceModel(persistence: persistence, calendar: calendar, date: date(1003))
        protected.play(.pomodoro, at: tick(1003), date: date(1003))
        expect(protected.loadFailed && defaults.data(forKey: persistence.key) == savedBytes, "Invalid completion history blocks mutation and preserves saved bytes")
        let configured = WorkspaceModel(calendar: calendar, focusDuration: 10, date: origin)
        configured.play(.pomodoro, at: tick(0), date: date(0))
        configured.updatePomodoroSettings(PomodoroSettings(focusMinutes: 1, shortBreakMinutes: 5, longBreakMinutes: 15, iterationsBeforeLongBreak: 4), at: tick(4), date: date(4))
        configured.synchronize(at: tick(12), date: date(12))
        expect(configured.ledger.completedPomodoros.first?.focusDuration == 10, "Settings preserve active interval completion duration")
        configured.play(.pomodoro, at: tick(13), date: date(13))
        configured.reset(.pomodoro, at: tick(20), date: date(20))
        expect(configured.ledger.completedPomodoros.count == 1, "Reset of next partial interval cannot replay previous completion")
        if let project = configured.ledger.entries.first?.project {
            configured.removeTimesheetProject(project, dayIDs: configured.ledger.entries.map(\.dayID), at: tick(21), date: date(21))
            configured.undoTimesheetRemoval(at: tick(22), date: date(22))
        }
        expect(configured.ledger.completedPomodoros.count == 1, "Weekly removal and Undo leave completion history unchanged")
        print("Passed \(checks) Pomodoro completion checks")
    }
}
