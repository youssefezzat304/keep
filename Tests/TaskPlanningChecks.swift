import AVFoundation
import Foundation
import Observation

private final class PlanningChangeFlag { var changed = false }

@main enum TaskPlanningChecks {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let day = "2026-10-12", tomorrow = "2026-10-13"
        guard let date = TaskDay.date(for: day, calendar: calendar), let future = TaskDay.date(for: tomorrow, calendar: calendar) else { throw CocoaError(.coderInvalidValue) }
        let clock = ContinuousClock.now
        func at(_ seconds: Double) -> ContinuousClock.Instant { clock.advanced(by: .seconds(seconds)) }
        func civil(_ seconds: Double) -> Date { date.addingTimeInterval(seconds) }
        let a = FocusTask(title: "Read", estimateMinutes: 30), b = FocusTask(title: "Read")
        let later = FocusTask(title: "Future plan", estimateMinutes: 45)
        let habits = HabitStore(calendar: calendar)
        let habit = try habits.add(name: "Reading", icon: .book, startDay: day, endDay: nil, goal: .amount(target: 30, unit: .minutes))
        let tasks = DailyTaskStore(archive: TaskArchive(days: [day: [a, b], tomorrow: [later]]), calendar: calendar, habits: habits)
        let preferences = AppPreferences()
        let workspace = WorkspaceModel(calendar: calendar, date: date, timerPreferences: preferences, tasks: tasks, habits: habits)
        let ref = TaskReference.task(id: a.id, dayID: day), other = TaskReference.task(id: b.id, dayID: day)
        workspace.startTask(a, on: day, timers: .both, at: at(0), date: civil(0))
        workspace.synchronize(at: at(60), date: civil(60))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 60, "Overlapping timers record one attributed minute")
        expect(workspace.readIndex.focusedSeconds(other, on: day) == 0, "Duplicate titles do not share actuals")
        let duplicates = WorkspaceModel(calendar: calendar, date: date, tasks: tasks)
        duplicates.startTask(a, on: day, timers: .flow, at: at(0), date: civil(0))
        duplicates.startTask(b, on: day, timers: .flow, at: at(60), date: civil(60))
        duplicates.stop(.flow, at: at(120), date: civil(120))
        expect(duplicates.ledger.sessions.count == 2 && duplicates.readIndex.focusedSeconds(ref, on: day) == 60
            && duplicates.readIndex.focusedSeconds(other, on: day) == 60, "Identical titles still split the recording context by task identity")
        try TimesheetPersistence.validate(duplicates.ledger)
        duplicates.shutdown(at: at(120), date: civil(120))
        try workspace.editTask(id: a.id, on: day, title: "  Renamed  ", estimateMinutes: 45, at: at(90), date: civil(90))
        expect(workspace.taskReference == ref && workspace.activeTaskName == "Renamed", "Rename retains identity and updates active context")
        workspace.startTask(b, on: day, timers: .flow, at: at(120), date: civil(120))
        workspace.stopBothTimers(at: at(180), date: civil(180))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 120 && workspace.readIndex.focusedSeconds(other, on: day) == 60,
            "Task switching settles the previous task before attribution changes")
        expect(workspace.taskSuggestions.filter { $0.taskReference != nil }.count == 2, "Recent tasks retain distinct identities")
        expect(workspace.ledger.sessions.contains { $0.task == "Read" } && workspace.ledger.sessions.contains { $0.task == "Renamed" }, "Recorded title snapshots survive renaming")
        try TimesheetPersistence.validate(workspace.ledger)
        tasks.setComplete(true, taskID: a.id, on: day)
        expect(tasks.tasks(on: day).compactMap(\.estimateMinutes).reduce(0, +) == 75, "Completing a task leaves the planned total including its habit goal")
        let capture = SnapshotCapture(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences)
        let snapshot = try capture.capture(.stats, at: at(180), date: civil(180))
        let request = ExportRequest(data: .taskEstimates, from: date, through: future, projectID: nil, taskKeys: nil)
        let report = try ExportReports.make(request, snapshot: snapshot)[0]
        let lines = String(decoding: report.contents, as: UTF8.self).components(separatedBy: "\r\n").filter { !$0.isEmpty }
        func columns(_ id: UUID) -> [String] { lines.first { $0.contains(id.uuidString) }?.components(separatedBy: ",") ?? [] }
        expect(columns(a.id)[4...6] == ["45", "2.00", "-43.00"], "Task report compares raw attributed seconds with the saved estimate")
        expect(columns(b.id)[4...6] == ["", "1.00", ""], "Unestimated tasks have blank planned and difference columns")
        expect(columns(later.id)[4...6] == ["45", "0.00", "-45.00"], "Future estimated tasks export with zero actuals")
        expect(lines.count == 6, "Task export includes daily timed-habit goals")
        let statsRequest = ExportRequest(data: .stats, from: date, through: date, projectID: nil, taskKeys: nil)
        let statsReports = try ExportReports.make(statsRequest, snapshot: snapshot)
        expect(statsReports.contains { $0.filename == "task_estimates.csv" }, "Stats ZIP includes task comparisons")
        do { try ExportRequest(data: .calendar, from: date, through: future, projectID: nil, taskKeys: nil).validate(now: date, calendar: calendar); preconditionFailure("Calendar future dates must remain invalid") } catch { checks += 1 }
        do { try ExportRequest(data: .taskEstimates, from: date, through: future, projectID: "x", taskKeys: nil).validate(now: date, calendar: calendar); preconditionFailure("Task comparison filters must be rejected") } catch { checks += 1 }
        guard let first = workspace.ledger.sessions.first, let project = workspace.selectedProject else { throw CocoaError(.coderInvalidValue) }
        try workspace.editSession(id: first.id, start: first.start, end: first.end.addingTimeInterval(30), at: at(180), date: civil(180))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 150, "Session edits change actuals by their duration delta")
        workspace.edit(seconds: 5000, project: project, dayID: day, at: at(180), date: civil(180))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 150, "Manual Timesheet totals never invent task attribution")
        try workspace.deleteSession(id: first.id, at: at(180), date: civil(180))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 30, "Session deletion removes task actuals")
        workspace.removeTimesheetProject(project, dayIDs: [day], at: at(180), date: civil(180))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 0, "Timesheet removal clears derived actuals")
        workspace.undoTimesheetRemoval(at: at(180), date: civil(180))
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 30 && workspace.readIndex.focusedSeconds(other, on: day) == 60, "Undo restores task references and actuals")
        workspace.startTask(a, on: day, timers: .flow, at: at(200), date: civil(200))
        workspace.removeTask(a, on: day, at: at(220), date: civil(220))
        workspace.synchronize(at: at(240), date: civil(240))
        expect(workspace.flow.phase(at: at(240)) == .running && workspace.taskReference == nil, "Removing an active ordinary task detaches future time without stopping")
        expect(workspace.readIndex.focusedSeconds(ref, on: day) == 50, "Removed task history retains settled linked time")
        let removed = try capture.capture(.stats, at: at(240), date: civil(240))
        let removedCSV = String(decoding: try ExportReports.make(request, snapshot: removed)[0].contents, as: UTF8.self)
        expect(removedCSV.contains("Renamed,removed,,0.83,,task"), "Deleted task report keeps its saved title and blanks unavailable planning fields")
        workspace.setTaskName("A new free-form target", at: at(250), date: civil(250))
        expect(workspace.taskReference == nil, "Free-form target changes cannot inherit a task link")
        workspace.shutdown(at: at(250), date: civil(250))

        let progressHabits = HabitStore(calendar: calendar)
        let reading = try progressHabits.add(name: "Read daily", icon: .book, startDay: day, endDay: nil, goal: .amount(target: 2, unit: .minutes))
        _ = progressHabits.setAmount(1, habitID: reading.id, on: day, today: date)
        let progressTasks = DailyTaskStore(calendar: calendar, habits: progressHabits)
        let model = WorkspaceModel(calendar: calendar, focusDuration: 60, breakDuration: 30, date: date,
            timerPreferences: preferences, tasks: progressTasks, habits: progressHabits)
        var sounds: [TimerSound] = []
        model.onTimerReminder = { sounds.append($0) }
        guard let row = progressTasks.tasks(on: day).first else { throw CocoaError(.coderInvalidValue) }
        func tick(_ seconds: Double) { model.synchronize(at: at(seconds), date: civil(seconds)) }
        model.startTask(row, on: day, timers: .both, at: at(0), date: civil(0))
        tick(59)
        expect(progressHabits.amount(for: reading, on: day) == 1 && sounds.isEmpty, "Partial minutes cannot meet a timed goal early")
        tick(60)
        expect(progressHabits.amount(for: reading, on: day) == 2 && progressTasks.tasks(on: day).first?.isComplete == true, "Manual and timer minutes automatically complete the habit")
        expect(sounds == [.focusComplete, .habitComplete], "Concurrent Pomodoro and habit completion emit distinct cues")
        tick(120)
        expect(progressHabits.amount(for: reading, on: day) == 3 && model.flow.phase(at: at(120)) == .running && sounds.count == 2, "Goal overshoot keeps counting without repeated cue or timer stop")
        expect(progressHabits.archive.logs.first?.amount == 1, "Automatic progress is never written into manual logs")
        expect(progressHabits.activity(today: date).total == 1 && progressHabits.statistics(for: reading, month: date, today: date).totalCompletions == 1, "Activity and statistics use combined progress")
        model.stop(.flow, at: at(150), date: civil(150)); tick(500)
        expect(progressHabits.timedSeconds(habitID: reading.id, on: day) == 150, "Paused Flow adds no habit time")
        model.play(.flow, at: at(500), date: civil(500)); tick(530)
        expect(progressHabits.timedSeconds(habitID: reading.id, on: day) == 180, "Resume continues accumulating habit time")
        model.reset(.flow, at: at(530), date: civil(530)); model.play(.flow, at: at(532), date: civil(532)); tick(562)
        expect(progressHabits.timedSeconds(habitID: reading.id, on: day) == 210, "Reset preserves previously recorded habit time")
        model.stop(.flow, at: at(562), date: civil(562))
        progressHabits.beforeManualEdit = { model.synchronize(at: at(562), date: civil(562)) }
        _ = progressHabits.setAmount(0, habitID: reading.id, on: day, today: date)
        expect(progressHabits.amount(for: reading, on: day) == 3 && sounds.count == 2, "Clearing manual minutes leaves recorded progress intact")
        for session in model.ledger.sessions { try model.deleteSession(id: session.id, at: at(562), date: civil(562)) }
        expect(progressHabits.amount(for: reading, on: day) == 0, "Deleting recorded sessions updates habit progress")
        _ = progressHabits.activity(today: date)
        let activityChange = PlanningChangeFlag()
        withObservationTracking { _ = progressHabits.activity(today: date) } onChange: {
            MainActor.assumeIsolated { activityChange.changed = true }
        }
        model.play(.flow, at: at(600), date: civil(600)); tick(720)
        expect(activityChange.changed && progressHabits.activity(today: date).total == 1, "Cached activity readers observe timer progress even after the daily cue is consumed")
        expect(sounds.count == 2 && progressHabits.isComplete(reading, on: day), "Corrections cannot rearm an already consumed daily cue")
        let muted = try progressHabits.add(name: "Muted", icon: .leaf, startDay: day, endDay: nil, goal: .amount(target: 1, unit: .minutes))
        guard let mutedRow = progressTasks.tasks(on: day).first(where: { $0.id == muted.id }) else { throw CocoaError(.coderInvalidValue) }
        preferences.timerSoundsEnabled = false
        model.startTask(mutedRow, on: day, timers: .flow, at: at(720), date: civil(720)); tick(780)
        preferences.timerSoundsEnabled = true; tick(781)
        expect(sounds.count == 2 && progressHabits.archive.consumedTimerGoals?[muted.id]?.contains(day) == true, "Muted completion is consumed and never replayed")
        model.stop(.flow, at: at(781), date: civil(781))
        let backupCapture = SnapshotCapture(workspace: model, tasks: progressTasks, habits: progressHabits, preferences: preferences)
        let payload = try backupCapture.capture(.backup, at: at(781), date: civil(781)).backupPayload()
        try payload.validate()
        let decoded = try JSONDecoder().decode(BackupPayload.self, from: JSONEncoder().encode(payload))
        expect(decoded.habits.logs.isEmpty && decoded.habits.consumedTimerGoals?[reading.id]?.contains(day) == true, "Backups keep manual logs separate and retain consumed goal markers")
        let restoredHabits = HabitStore(archive: decoded.habits, calendar: calendar)
        let restoredTasks = DailyTaskStore(archive: decoded.tasks, calendar: calendar, habits: restoredHabits)
        let restored = WorkspaceModel(ledger: decoded.workspace, calendar: calendar, date: date, timerPreferences: preferences, tasks: restoredTasks, habits: restoredHabits)
        expect(restoredHabits.amount(for: reading, on: day) == 2, "Relaunch rebuilds automatic habit totals from sessions")
        restored.installBackup(TimesheetLedger())
        expect(restoredHabits.amount(for: reading, on: day) == 0, "Restore rebuilds projection instead of retaining stale automatic counters")
        model.shutdown(at: at(781), date: civil(781)); restored.shutdown()

        // The real restore gate is locked while both stores are installed.
        let suite = "keep.planning.restore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = BackupRestoreGate()
        var hp = HabitPersistence(defaults: defaults); hp.access = gate
        try hp.save(decoded.habits)
        let gatedHabits = HabitStore(persistence: hp, calendar: calendar)
        let gatedTasks = DailyTaskStore(calendar: calendar, habits: gatedHabits)
        let gatedModel = WorkspaceModel(calendar: calendar, date: date, timerPreferences: preferences, tasks: gatedTasks, habits: gatedHabits)
        var restoredCues: [TimerSound] = []; gatedModel.onTimerReminder = { restoredCues.append($0) }
        var withoutMarkers = decoded.habits; withoutMarkers.consumedTimerGoals = nil
        gate.isLocked = true
        gatedModel.installBackup(decoded.workspace); gatedHabits.installBackup(withoutMarkers)
        expect(gatedHabits.amount(for: reading, on: day) == 2, "Derived progress rebuilds during a locked restore without persisting counters")
        gate.isLocked = false
        gatedModel.synchronize(at: at(0), date: date)
        expect(restoredCues.isEmpty && gatedHabits.archive.consumedTimerGoals?[reading.id]?.contains(day) == true,
            "Unlocking restore consumes historical goals silently")
        gatedModel.shutdown(at: at(0), date: date)

        // Civil-day habit occurrences and ordinary tasks spanning midnight.
        let midnight = calendar.startOfDay(for: date).addingTimeInterval(86370)
        let crossingHabits = HabitStore(calendar: calendar)
        let crossingHabit = try crossingHabits.add(name: "Across midnight", icon: .sleep, startDay: day, endDay: nil, goal: .amount(target: 1, unit: .minutes))
        let crossingTasks = DailyTaskStore(archive: TaskArchive(days: [day: [a]]), calendar: calendar, habits: crossingHabits)
        let crossing = WorkspaceModel(calendar: calendar, date: midnight, timerPreferences: preferences, tasks: crossingTasks, habits: crossingHabits)
        var crossingSounds: [TimerSound] = []; crossing.onTimerReminder = { crossingSounds.append($0) }
        guard let crossingRow = crossingTasks.tasks(on: day).first(where: { $0.habitID != nil }) else { throw CocoaError(.coderInvalidValue) }
        crossing.startTask(crossingRow, on: day, timers: .flow, at: at(0), date: midnight)
        crossing.synchronize(at: at(120), date: midnight.addingTimeInterval(120))
        expect(crossingHabits.timedSeconds(habitID: crossingHabit.id, on: day) == 30 && crossingHabits.timedSeconds(habitID: crossingHabit.id, on: tomorrow) == 90,
            "Habit recording splits at civil midnight")
        expect(crossingSounds == [.habitComplete], "Only the new day's reached goal sounds")
        crossing.shutdown(at: at(120), date: midnight.addingTimeInterval(120))
        let ordinaryCrossing = WorkspaceModel(calendar: calendar, date: midnight, tasks: crossingTasks)
        ordinaryCrossing.startTask(a, on: day, timers: .flow, at: at(0), date: midnight)
        ordinaryCrossing.stop(.flow, at: at(120), date: midnight.addingTimeInterval(120))
        expect(ordinaryCrossing.readIndex.focusedSeconds(ref, on: day) == 120 && ordinaryCrossing.ledger.sessions.count == 2, "Ordinary task actuals span midnight while Calendar retains both civil days")
        ordinaryCrossing.shutdown(at: at(120), date: midnight.addingTimeInterval(120))

        let correctedHabits = HabitStore(calendar: calendar)
        let correctedHabit = try correctedHabits.add(name: "Corrected habit", icon: .study, startDay: day, endDay: nil, goal: .amount(target: 1, unit: .minutes))
        let correctedTasks = DailyTaskStore(calendar: calendar, habits: correctedHabits)
        var correctedLedger = TimesheetLedger()
        correctedLedger.record(project: .unassigned, from: date, seconds: 30, calendar: calendar, sessionID: UUID(), task: correctedHabit.name, source: .flow, taskReference: .habit(id: correctedHabit.id))
        let correctedModel = WorkspaceModel(ledger: correctedLedger, calendar: calendar, date: date, timerPreferences: preferences, tasks: correctedTasks, habits: correctedHabits)
        var correctionSounds: [TimerSound] = []; correctedModel.onTimerReminder = { correctionSounds.append($0) }
        guard let correctedSession = correctedModel.ledger.sessions.first else { throw CocoaError(.coderInvalidValue) }
        try correctedModel.editSession(id: correctedSession.id, start: correctedSession.start, end: correctedSession.start.addingTimeInterval(70), at: at(0), date: date)
        expect(correctionSounds.isEmpty && correctedHabits.isComplete(correctedHabit, on: day)
            && correctedHabits.archive.consumedTimerGoals?[correctedHabit.id]?.contains(day) == true, "A historical edit can complete a habit without sounding or rearming its goal")
        try correctedModel.deleteSession(id: correctedSession.id, at: at(0), date: date)
        expect(!correctedHabits.isComplete(correctedHabit, on: day), "Session correction updates automatic completion")
        correctedModel.shutdown(at: at(0), date: date)
        var alternate = Calendar(identifier: .buddhist); alternate.timeZone = .gmt
        let alternateModel = WorkspaceModel(calendar: alternate, date: date, tasks: tasks)
        alternateModel.startTask(b, on: day, timers: .flow, at: at(0), date: date)
        alternateModel.stop(.flow, at: at(60), date: civil(60))
        expect(alternateModel.ledger.sessions.first?.dayID == day && alternateModel.readIndex.focusedSeconds(other, on: day) == 60,
            "Task and habit attribution uses Gregorian civil keys even with another system calendar")
        alternateModel.shutdown(at: at(60), date: civil(60))

        let legacyTask = try JSONDecoder().decode(FocusTask.self, from: Data("{\"id\":\"\(a.id)\",\"title\":\"Old task\",\"isComplete\":false}".utf8))
        expect(legacyTask.estimateMinutes == nil, "Old task archives default to no estimate")
        let legacyHabit = try JSONDecoder().decode(HabitArchive.self, from: Data("{\"habits\":[],\"logs\":[]}".utf8))
        expect(legacyHabit.consumedTimerGoals == nil, "Old habit archives have no cue markers")
        var unlinked = TimesheetLedger()
        unlinked.record(project: .unassigned, from: date, seconds: 60, calendar: calendar, sessionID: UUID(), task: a.title)
        expect(TaskTimeTotals(sessions: unlinked.sessions).seconds.isEmpty, "Legacy title-only sessions are not guessed into task actuals")
        for invalid in [0, -1, 1441] {
            do { try tasks.update(taskID: b.id, on: day, title: "Valid", estimateMinutes: invalid); preconditionFailure("Reject estimate") } catch { checks += 1 }
        }
        var totals = TaskTimeTotals()
        for offset in [0.0, 30.0] {
            let session = RecordedSession(id: UUID().uuidString, recordingID: UUID(), dayID: day, project: .unassigned, task: "Partial", source: .flow, timeZoneID: "GMT", start: date.addingTimeInterval(offset), end: date.addingTimeInterval(offset + 30), taskReference: .habit(id: habit.id))
            totals.adjust(session, multiplier: 1)
        }
        expect(totals.focused(.habit(id: habit.id), on: day) == 60, "Fractional sessions accumulate before whole-minute display")
        let audio = TimerSoundPlayer(); audio.play(.habitComplete)
        for _ in 0..<60 {
            if !audio.isPlaying { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if audio.isPlaying || audio.errorMessage != nil { print("Habit cue playback: playing=\(audio.isPlaying), error=\(audio.errorMessage ?? "none")") }
        expect(!audio.isPlaying && audio.errorMessage == nil, "The new distinct habit cue plays natively")
        let missing = TimerSoundPlayer(bundle: Bundle(for: NSObject.self)); missing.play(.habitComplete)
        try await Task.sleep(for: .milliseconds(200))
        expect(missing.errorMessage != nil && !missing.isPlaying, "Missing audio produces an actionable error without a stuck player")
        print("Passed \(checks) task identity, estimates, habit recording, goal cue, export and compatibility checks")
    }
}
