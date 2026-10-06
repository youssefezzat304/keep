import Foundation

@main enum SessionRecordingChecks {
    private static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }
    static func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.001 }

    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9)) ?? .now
        let instant = ContinuousClock.now
        func time(_ seconds: Int) -> ContinuousClock.Instant { instant.advanced(by: .seconds(seconds)) }
        func wall(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        let workspace = WorkspaceModel(calendar: calendar, focusDuration: 10, breakDuration: 5, date: date)
        workspace.setTaskName("First task", at: instant, date: date)
        workspace.play(.pomodoro, at: instant, date: date)
        workspace.synchronize(at: time(3), date: wall(3))
        workspace.synchronize(at: time(5), date: wall(5))
        expect(workspace.ledger.sessions.count == 1, "UI refreshes coalesce into one session")
        expect(close(workspace.ledger.sessions[0].seconds, 5), "Record elapsed focus")
        expect(workspace.ledger.sessions[0].task == "First task", "Capture task name")
        workspace.play(.flow, at: time(5), date: wall(5))
        workspace.synchronize(at: time(15), date: wall(15))
        expect(workspace.ledger.sessions.count == 2, "Flow override starts a distinct interval")
        expect(workspace.ledger.sessions[1].source == .flow, "Label the winning timer")
        expect(close(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }, 15), "Overlap is counted once")
        workspace.startBreak(at: time(15), date: wall(15))
        workspace.synchronize(at: time(18), date: wall(18))
        expect(close(workspace.ledger.sessions[1].seconds, 13), "Flow counts through a Pomodoro break")
        workspace.stop(.flow, at: time(18), date: wall(18))
        workspace.synchronize(at: time(30), date: wall(30))
        expect(workspace.ledger.sessions.count == 2, "Pomodoro breaks create no sessions")
        workspace.play(.pomodoro, at: time(30), date: wall(30))
        workspace.stop(.pomodoro, at: time(34), date: wall(34))
        workspace.play(.pomodoro, at: time(40), date: wall(40))
        workspace.stop(.pomodoro, at: time(42), date: wall(42))
        expect(workspace.ledger.sessions.count == 4, "Pause/resume excludes gaps and splits blocks")
        expect(close(workspace.ledger.sessions[3].seconds, 2), "Resumed interval has exact duration")
        workspace.play(.flow, at: time(45), date: wall(45))
        workspace.setTaskName("Second task", at: time(48), date: wall(48))
        workspace.selectProject(FocusProject.defaults[1], at: time(50), date: wall(50))
        workspace.stop(.flow, at: time(53), date: wall(53))
        let recent = Array(workspace.ledger.sessions.suffix(3))
        expect(recent.map(\.task) == ["First task", "Second task", "Second task"], "Task changes settle the previous interval")
        expect(recent.map { $0.project.id } == ["keep", "keep", "german"], "Project changes settle the previous project")
        expect(close(workspace.ledger.entries.reduce(0) { $0 + $1.seconds }, workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }), "Daily totals and timer sessions agree")
        let dayID = TimesheetWeek.dayID(for: date, calendar: calendar)
        let originalSessionTime = workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }
        workspace.edit(seconds: 500, project: FocusProject.defaults[0], dayID: dayID, at: time(53), date: wall(53))
        expect(close(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }, originalSessionTime), "Manual totals do not invent session timestamps")
        let removed = workspace.ledger.sessions.filter { $0.project.id == "keep" }.count
        workspace.removeTimesheetProject(FocusProject.defaults[0], dayIDs: [dayID], at: time(54), date: wall(54))
        expect(workspace.ledger.sessions.allSatisfy { $0.project.id != "keep" }, "Removing a row also removes its sessions")
        workspace.undoTimesheetRemoval(at: time(54), date: wall(54))
        expect(workspace.ledger.sessions.filter { $0.project.id == "keep" }.count == removed, "Undo restores session history")

        let focus = WorkspaceModel(calendar: calendar, focusDuration: 10, breakDuration: 5, date: date)
        focus.play(.pomodoro, at: instant, date: date)
        focus.synchronize(at: time(20), date: wall(20))
        expect(close(focus.ledger.sessions[0].seconds, 10), "Late completion ends at the focus boundary")
        focus.startBreak(at: time(20), date: wall(20))
        focus.synchronize(at: time(30), date: wall(30))
        expect(focus.ledger.sessions.count == 1, "A standalone break records no interval")

        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 59, second: 55)) ?? date
        let cross = WorkspaceModel(calendar: calendar, date: midnight)
        cross.selectProject(nil, at: instant, date: midnight)
        cross.play(.flow, at: instant, date: midnight)
        cross.stop(.flow, at: time(15), date: midnight.addingTimeInterval(15))
        expect(cross.ledger.sessions.count == 2, "Midnight creates two civil-day segments")
        expect(cross.ledger.sessions.map(\.seconds) == [5, 10], "Split midnight accurately")
        expect(cross.ledger.sessions[0].endMinute == 1440, "Midnight endpoint renders at 24:00")
        expect(cross.ledger.sessions[1].startMinute == 0, "Next day starts at midnight")
        expect(cross.ledger.sessions.allSatisfy { $0.project == .unassigned }, "Unassigned sessions are retained")
        cross.shutdown(at: time(20), date: midnight.addingTimeInterval(20))
        expect(close(cross.ledger.sessions.reduce(0) { $0 + $1.seconds }, 15), "Shutdown after stopping adds no time")

        let jump = WorkspaceModel(calendar: calendar, date: date)
        jump.play(.flow, at: instant, date: date)
        jump.synchronize(at: time(2), date: wall(3602))
        jump.synchronize(at: time(4), date: wall(3604))
        jump.synchronize(at: time(6), date: wall(3606))
        expect(jump.ledger.sessions.count == 2, "Wall-clock jumps split without per-tick fragmentation")
        expect(close(jump.ledger.sessions.reduce(0) { $0 + $1.seconds }, 6), "Wall jumps do not change elapsed duration")

        for (month, day, hours) in [(3, 29, 23), (10, 25, 25)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day)) ?? date
            let dst = WorkspaceModel(calendar: calendar, date: start)
            dst.play(.flow, at: instant, date: start)
            dst.stop(.flow, at: time(hours * 3600 + 10), date: start.addingTimeInterval(Double(hours * 3600 + 10)))
            expect(dst.ledger.sessions.count == 2, "Split a DST day at calendar midnight")
            expect(close(dst.ledger.sessions[0].seconds, Double(hours * 3600)), "Use the actual DST day duration")
        }
        let active = WorkspaceModel(calendar: calendar, date: date)
        active.play(.flow, at: instant, date: date)
        active.removeTimesheetProject(FocusProject.defaults[0], dayIDs: [dayID], at: time(5), date: wall(5))
        active.synchronize(at: time(8), date: wall(8))
        active.undoTimesheetRemoval(at: time(8), date: wall(8))
        active.stop(.flow, at: time(10), date: wall(10))
        expect(close(active.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Undo preserves newly recorded sessions")
        expect(Set(active.ledger.sessions.map(\.id)).count == active.ledger.sessions.count, "Restored sessions have unique identifiers")

        let suite = "keep.session-checks.\(UUID().uuidString)"
        let taskActions = WorkspaceModel(calendar: calendar, focusDuration: 10, breakDuration: 5, date: date)
        taskActions.startTask("  Focus task  ", timers: .focus, at: instant, date: date)
        expect(taskActions.taskName == "Focus task", "Task actions trim and commit the selected title")
        expect(taskActions.pomodoro.phase(at: instant) == .running && taskActions.flow.phase(at: instant) == .idle, "Focus starts only Pomodoro")
        taskActions.startTask("Flow task", timers: .flow, at: time(4), date: wall(4))
        expect(taskActions.ledger.sessions[0].task == "Focus task" && close(taskActions.ledger.sessions[0].seconds, 4), "Task launch settles time under the previous title")
        expect(taskActions.pomodoro.phase(at: time(4)) == .running, "Flow action leaves a running Pomodoro untouched")
        taskActions.stop(.flow, at: time(7), date: wall(7))
        taskActions.synchronize(at: time(10), date: wall(10))
        taskActions.startBreak(at: time(10), date: wall(10))
        taskActions.startTask("Next focus", timers: .focus, at: time(12), date: wall(12))
        expect(taskActions.pomodoro.interval == .focus && taskActions.pomodoro.phase(at: time(12)) == .running, "Focus task leaves an active break for a focus interval")
        expect(taskActions.pomodoro.completedFocusIntervals == 1, "Leaving a short break preserves the focus cycle")
        expect(taskActions.flow.phase(at: time(12)) == .stopped, "Focus action leaves paused Flow untouched")
        taskActions.startTask("Together", timers: .both, at: time(15), date: wall(15))
        expect(taskActions.pomodoro.phase(at: time(15)) == .running && taskActions.flow.phase(at: time(15)) == .running, "Both action starts the two independent timers")
        taskActions.stop(.flow, at: time(18), date: wall(18))
        expect(taskActions.ledger.sessions.last?.task == "Together" && taskActions.ledger.sessions.last?.source == .flow, "Both action records once with Flow priority and the selected title")
        expect(close(taskActions.ledger.sessions.reduce(0) { $0 + $1.seconds }, 16), "Task changes and overlap preserve exact recorded totals and exclude breaks")

        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        try persistence.save(workspace.ledger)
        let loaded = try persistence.load()
        expect(loaded.sessions.count == workspace.ledger.sessions.count, "Reload session history")
        expect(close(loaded.sessions.reduce(0) { $0 + $1.seconds }, originalSessionTime), "Reload exact recorded duration")
        let legacy = Data("{\"entries\":[]}".utf8)
        defaults.set(legacy, forKey: persistence.key)
        let oldLedger = try persistence.load()
        expect(oldLedger.sessions.isEmpty, "Old archives load without sessions")
        let fresh = WorkspaceModel(persistence: persistence, calendar: calendar)
        expect(fresh.ledger.sessions.isEmpty && fresh.taskName.isEmpty, "No mock sessions or restored runtime drafts")
        var corrupt = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any] ?? [:]
        var sessions = corrupt["sessions"] as? [[String: Any]] ?? []
        sessions[0]["end"] = sessions[0]["start"]
        corrupt["sessions"] = sessions
        let badData = try JSONSerialization.data(withJSONObject: corrupt)
        defaults.set(badData, forKey: persistence.key)
        let blocked = WorkspaceModel(persistence: persistence)
        expect(blocked.loadFailed, "Reject invalid session ranges")
        blocked.play(.flow)
        expect(defaults.data(forKey: persistence.key) == badData, "Invalid data is not overwritten")
        print("Passed \(checks) session recording checks")
    }
}
