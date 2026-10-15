import Foundation

@main enum AutomaticPomodoroBreakChecks {
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
            expect(workspace.pomodoro.interval == .rest && workspace.pomodoro.phase(at: at(10)) == .running, "Focus completion starts the optional break without a notch action")
            expect(workspace.pomodoro.seconds(at: at(10)) == 5, "The full break starts when completion is delivered")
            expect(notice?.usesBreakScreen(timer: workspace.pomodoro) == true && notice?.isCurrent(timer: workspace.pomodoro, at: at(10)) == true, "The pending focus cue belongs to the break screen instead of an expanded notch")
            expect(workspace.ledger.completedPomodoros.count == 1 && workspace.pomodoro.completedFocusIntervals == 1, "Automatic transition counts exactly one focus interval")
            expect(near(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Only completed focus contributes recorded Pomodoro time")
            expect(cues == (animation ? [.focusComplete] : []), "Automatic break does not couple visual delivery to sound enablement")
            tick(workspace, 11)
            workspace.selectProject(.defaults[1], at: at(11), date: day(11))
            expect(workspace.pomodoro.seconds(at: at(11)) == 4 && workspace.pomodoroCompletion == notice, "Refreshes and unrelated saves retain the break countdown and unacknowledged sound")
            tick(workspace, 15)
            expect(workspace.pomodoro.interval == .rest && workspace.pomodoro.phase(at: at(15)) == .completed, "Break completion waits for the user to start focus")
            expect(workspace.pomodoroCompletion?.isBreak == true && workspace.pomodoroCompletion?.usesBreakScreen(timer: workspace.pomodoro) == false, "Break completion replaces the focus notice once")
            expect(cues == (animation ? [.focusComplete, .breakComplete] : []), "Each boundary delivers at most one completion cue")
            expect(near(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Automatic breaks never inflate focus totals")
            workspace.shutdown(at: at(15), date: day(15))
        }

        let options = AppPreferences(); options.blurPomodoroBreaks = true
        let cycles = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: options)
        var cues: [TimerSound] = []; cycles.onTimerReminder = { cues.append($0) }
        cycles.startBothTimers(at: at(0), date: day(0))
        for cycle in 1...4 {
            let end = (cycle - 1) * 15 + 10
            tick(cycles, end); tick(cycles, end)
            expect(cycles.pomodoro.interval == .rest && cycles.pomodoro.phase(at: at(end)) == .running, "Each completed focus starts a break once")
            expect(cycles.pomodoro.isLongBreak == (cycle == 4), "The existing fourth-interval long-break cycle is preserved")
            expect(cycles.pomodoro.seconds(at: at(end)) == (cycle == 4 ? 900 : 5), "Automatic breaks use the configured short/long duration")
            expect(cycles.ledger.completedPomodoros.count == cycle && cues.filter { $0 == .focusComplete }.count == cycle, "Repeated synchronization never duplicates cycle progress or cues")
            expect(cycles.flow.phase(at: at(end)) == .running && near(cycles.flow.elapsed(at: at(end)), Double(end)), "Concurrent Flow stays independent during automatic breaks")
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
        expect(late.pomodoro.seconds(at: at(100)) == 5 && late.pomodoro.interval == .rest, "A late refresh or wake delivers one full break rather than replaying missed phases")
        expect(late.ledger.completedPomodoros.first?.completedAt == day(10) && near(late.ledger.sessions.reduce(0) { $0 + $1.seconds }, 10), "Late delivery retains the actual focus boundary and capped recording")
        late.stop(.pomodoro, at: at(102), date: day(102)); tick(late, 500)
        expect(late.pomodoro.phase(at: at(500)) == .stopped && late.pomodoro.seconds(at: at(500)) == 3 && late.pomodoroCompletion == nil, "Pausing acknowledges the notice and freezes the remaining break")
        late.play(.pomodoro, at: at(501), date: day(501)); tick(late, 504)
        expect(late.pomodoro.phase(at: at(504)) == .completed && late.ledger.completedPomodoros.count == 1, "Resume finishes the same break without another focus completion")
        late.shutdown(at: at(504), date: day(504))

        let manualOptions = AppPreferences()
        let manual = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: manualOptions)
        manual.play(.pomodoro, at: at(0), date: day(0)); tick(manual, 10)
        expect(manual.pomodoro.interval == .focus && manual.pomodoro.phase(at: at(10)) == .completed, "With blur off, existing manual break behavior remains")
        manualOptions.blurPomodoroBreaks = true; tick(manual, 11)
        expect(manual.pomodoro.interval == .focus && manual.pomodoro.phase(at: at(11)) == .completed, "Enabling blur cannot replay an already delivered completion")
        manual.startBreak(at: at(11), date: day(11))
        expect(manual.pomodoro.interval == .rest && manual.pomodoroCompletion == nil, "An explicit break action acknowledges its completion")
        manual.skipPomodoroBreak(at: at(12), date: day(12))
        expect(manual.pomodoro.interval == .focus && manual.pomodoro.phase(at: at(12)) == .running && manual.pomodoro.completedFocusIntervals == 1, "Skip retains the normal cycle and starts a fresh focus interval")
        manual.reset(.pomodoro, at: at(22), date: day(22))
        expect(manual.pomodoro.phase(at: at(22)) == .idle && manual.pomodoroCompletion == nil && manual.ledger.completedPomodoros.count == 2, "Reset at a boundary cancels the automatically started break without losing completion history")
        manual.shutdown(at: at(22), date: day(22))

        let suite = "keep.automatic-breaks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = BackupRestoreGate()
        var persistence = SettingsPersistence(defaults: defaults); persistence.access = gate
        let protectedOptions = AppPreferences(persistence: persistence); protectedOptions.blurPomodoroBreaks = true
        gate.isLocked = true
        let protected = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: protectedOptions)
        protected.play(.pomodoro, at: at(0), date: day(0)); tick(protected, 10)
        expect(protected.pomodoro.interval == .focus && protected.pomodoro.phase(at: at(10)) == .completed, "Unavailable settings cannot initiate automatic screen breaks")
        gate.isLocked = false; tick(protected, 11)
        expect(protected.pomodoro.interval == .focus && protected.ledger.completedPomodoros.count == 1, "Unlocking restore cannot replay old automatic transitions")
        protected.shutdown(at: at(11), date: day(11))
        print("Passed \(checks) automatic Pomodoro break, cue lifecycle and recording checks")
    }
}
