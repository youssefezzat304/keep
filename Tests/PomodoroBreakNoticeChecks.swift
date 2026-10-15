import Foundation

@main enum PomodoroBreakNoticeChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    static func main() throws {
        let clock = ContinuousClock.now, date = Date(timeIntervalSince1970: 1_792_058_400)
        func at(_ seconds: Int) -> ContinuousClock.Instant { clock + .seconds(seconds) }
        func day(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        func tick(_ workspace: WorkspaceModel, _ seconds: Int) { workspace.synchronize(at: at(seconds), date: day(seconds)) }
        for (timer, animation) in [(false, false), (false, true), (true, false), (true, true)] {
            let options = AppPreferences()
            options.blurPomodoroBreaks = true; options.notchPomodoroTimer = timer; options.notchPomodoroCompletion = animation
            options.timerSoundsEnabled = animation
            let workspace = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: options)
            var cues: [TimerSound] = []; workspace.onTimerReminder = { cues.append($0) }
            workspace.play(.pomodoro, at: at(0), date: day(0))
            tick(workspace, 10)
            let notice = workspace.pomodoroCompletion
            expect(workspace.pomodoro.interval == .focus && workspace.pomodoro.phase(at: at(10)) == .completed, "Focus completion waits for an explicit break action even with screen blur enabled")
            expect(workspace.pomodoro.upcomingBreakDuration(at: at(10)) == 5, "The pending screen offers the full configured break")
            expect(notice?.isBreak == false && notice?.isCurrent(timer: workspace.pomodoro, at: at(10)) == true, "Focus completion remains available for visual and sound acknowledgement")
            expect(workspace.ledger.completedPomodoros.count == 1 && workspace.pomodoro.completedFocusIntervals == 1, "Completion counts exactly one focus interval")
            expect(near(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Only completed focus contributes recorded Pomodoro time")
            expect(cues == (animation ? [.focusComplete] : []), "Visual completion does not depend on sound enablement")
            tick(workspace, 11)
            workspace.selectProject(.defaults[1], at: at(11), date: day(11))
            expect(workspace.pomodoro.interval == .focus && workspace.pomodoroCompletion == notice, "Refreshes and unrelated saves retain the pending notice without starting rest")
            tick(workspace, 100)
            expect(workspace.pomodoro.interval == .focus && workspace.pomodoroCompletion == notice && workspace.pomodoro.completedFocusIntervals == 1, "Waiting beyond the break duration cannot start or complete rest")
            expect(cues == (animation ? [.focusComplete] : []), "Waiting cannot produce a break-complete sound")
            workspace.startBreak(at: at(100), date: day(100))
            expect(workspace.pomodoro.interval == .rest && workspace.pomodoro.phase(at: at(100)) == .running && workspace.pomodoro.seconds(at: at(100)) == 5, "Explicit Start break starts the full countdown at the action time")
            expect(workspace.pomodoroCompletion == nil && notice?.isCurrent(timer: workspace.pomodoro, at: at(100)) == false, "Starting rest acknowledges the focus notice")
            tick(workspace, 105)
            expect(workspace.pomodoro.interval == .rest && workspace.pomodoro.phase(at: at(105)) == .completed, "Break completion waits for the user to start focus")
            expect(workspace.pomodoroCompletion?.isBreak == true, "A started break produces its own completion notice once")
            expect(cues == (animation ? [.focusComplete, .breakComplete] : []), "Each boundary delivers at most one completion cue")
            expect(near(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Waiting and breaks never inflate focus totals")
            workspace.shutdown(at: at(105), date: day(105))
        }

        let options = AppPreferences(); options.blurPomodoroBreaks = true
        let cycles = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: options)
        var cues: [TimerSound] = []; cycles.onTimerReminder = { cues.append($0) }
        cycles.startBothTimers(at: at(0), date: day(0))
        for cycle in 1...4 {
            let end = (cycle - 1) * 15 + 10
            tick(cycles, end); tick(cycles, end)
            expect(cycles.pomodoro.interval == .focus && cycles.pomodoro.phase(at: at(end)) == .completed, "Each completed focus waits for Start break")
            expect(cycles.pomodoro.breakIsLong(at: at(end)) == (cycle == 4), "The pending screen offers a long break on the fourth interval")
            expect(cycles.pomodoro.upcomingBreakDuration(at: at(end)) == (cycle == 4 ? 900 : 5), "Pending breaks retain the configured short/long duration")
            expect(cycles.pomodoro.completedFocusIntervals == cycle, "Waiting preserves the cycle until a break is started")
            cycles.startBreak(at: at(end), date: day(end))
            expect(cycles.pomodoro.isLongBreak == (cycle == 4) && cycles.pomodoro.seconds(at: at(end)) == (cycle == 4 ? 900 : 5), "Start break begins the offered duration and cycle")
            expect(cycles.ledger.completedPomodoros.count == cycle && cues.filter { $0 == .focusComplete }.count == cycle, "Repeated synchronization never duplicates cycle progress or cues")
            expect(cycles.flow.phase(at: at(end)) == .running && near(cycles.flow.elapsed(at: at(end)), Double(end)), "Concurrent Flow stays independent while awaiting and running breaks")
            expect(near(cycles.ledger.sessions.reduce(0) { $0 + $1.seconds }, Double(end)) && cycles.ledger.sessions.allSatisfy { $0.source == .flow }, "Flow priority remains the sole source of overlapping recorded time")
            if cycle < 4 {
                tick(cycles, end + 5)
                cycles.play(.pomodoro, at: at(end + 5), date: day(end + 5))
            }
        }
        expect(cycles.pomodoro.completedFocusIntervals == 0, "Starting the long break consumes its cycle exactly once")
        cycles.shutdown(at: at(55), date: day(55))

        let late = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: options)
        late.play(.pomodoro, at: at(0), date: day(0)); tick(late, 100)
        expect(late.pomodoro.upcomingBreakDuration(at: at(100)) == 5 && late.pomodoro.interval == .focus && late.pomodoro.phase(at: at(100)) == .completed, "A late refresh or wake delivers completion without starting a break")
        expect(late.ledger.completedPomodoros.first?.completedAt == day(10) && near(late.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Late delivery retains the actual focus boundary and capped recording")
        late.dismissPomodoroCompletion(); tick(late, 500)
        expect(late.pomodoro.interval == .focus && late.pomodoro.phase(at: at(500)) == .completed && late.pomodoroCompletion == nil, "Dismissing the screen leaves the timer waiting indefinitely without replay")
        late.startBreak(at: at(500), date: day(500))
        late.stop(.pomodoro, at: at(502), date: day(502)); tick(late, 900)
        expect(late.pomodoro.phase(at: at(900)) == .stopped && late.pomodoro.seconds(at: at(900)) == 3, "A manually started break can still pause")
        late.play(.pomodoro, at: at(901), date: day(901)); tick(late, 904)
        expect(late.pomodoro.phase(at: at(904)) == .completed && late.ledger.completedPomodoros.count == 1, "Resume finishes the same break without another focus completion")
        late.shutdown(at: at(904), date: day(904))

        let manualOptions = AppPreferences()
        let manual = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: manualOptions)
        manual.play(.pomodoro, at: at(0), date: day(0)); tick(manual, 10)
        expect(manual.pomodoro.interval == .focus && manual.pomodoro.phase(at: at(10)) == .completed, "With blur off, existing manual break behavior remains")
        manualOptions.blurPomodoroBreaks = true; tick(manual, 11)
        expect(manual.pomodoro.interval == .focus && manual.pomodoro.phase(at: at(11)) == .completed, "Enabling blur cannot start an interval")
        manual.startBreak(at: at(11), date: day(11))
        expect(manual.pomodoro.interval == .rest && manual.pomodoroCompletion == nil, "An explicit break action acknowledges its completion")
        manual.skipPomodoroBreak(at: at(12), date: day(12))
        expect(manual.pomodoro.interval == .focus && manual.pomodoro.phase(at: at(12)) == .running && manual.pomodoro.completedFocusIntervals == 1, "Skip retains the normal cycle and starts a fresh focus interval")
        manual.reset(.pomodoro, at: at(22), date: day(22))
        expect(manual.pomodoro.phase(at: at(22)) == .idle && manual.pomodoroCompletion == nil && manual.ledger.completedPomodoros.count == 2, "Reset at a boundary clears the pending break notice without losing completion history")
        manual.shutdown(at: at(22), date: day(22))

        let suite = "keep.break-notices.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = BackupRestoreGate()
        var persistence = SettingsPersistence(defaults: defaults); persistence.access = gate
        let protectedOptions = AppPreferences(persistence: persistence); protectedOptions.blurPomodoroBreaks = true
        gate.isLocked = true
        let protected = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: protectedOptions)
        protected.play(.pomodoro, at: at(0), date: day(0)); tick(protected, 10)
        expect(protected.pomodoro.interval == .focus && protected.pomodoro.phase(at: at(10)) == .completed, "Unavailable settings leave break timing manual")
        gate.isLocked = false; tick(protected, 11)
        expect(protected.pomodoro.interval == .focus && protected.ledger.completedPomodoros.count == 1, "Unlocking restore cannot start a break or duplicate completion")
        protected.shutdown(at: at(11), date: day(11))
        print("Passed \(checks) Pomodoro break notice, manual start, cue lifecycle and recording checks")
    }
}
