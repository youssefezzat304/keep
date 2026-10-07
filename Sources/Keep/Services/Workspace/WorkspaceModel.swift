import Foundation
import Observation

/// Shared across windows and tabs. All timer actions settle the single recorder first.
@Observable
final class WorkspaceModel {
    enum TaskTimers: CaseIterable { case focus, flow, both }
    private(set) var pomodoro = FocusTimer(mode: .pomodoro)
    private(set) var flow = FocusTimer(mode: .flow)
    private(set) var selectedProject: FocusProject? = FocusProject.defaults.first
    private(set) var taskName = ""
    private(set) var ledger: TimesheetLedger
    private(set) var persistenceError: String?
    private(set) var loadFailed = false
    private(set) var today: Date
    /// Lets the status item use the workspace refresh without owning another timeline.
    private(set) var displayInstant = ContinuousClock.now
    private(set) var lastTimesheetRemoval: TimesheetRemoval?
    var canTrack: Bool { !loadFailed }
    let readIndex: WorkspaceReadIndex
    var projects: [FocusProject] { _ = readIndex.metadataRevision; return readIndex.activeProjects }
    var pomodoroSettings: PomodoroSettings { ledger.pomodoroSettings ?? .defaults }
    var taskSuggestions: [TaskActivity] { _ = readIndex.metadataRevision; return readIndex.suggestions }

    func selectTask(_ activity: TaskActivity, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, let current = taskSuggestions.first(where: { $0.id == activity.id }) else { return }
        synchronize(at: instant, date: date)
        selectedProject = projects.first { $0.id == current.project.id }
        taskName = current.title
        if isRecording(at: instant) { ensureCurrentRow(on: date); rememberCurrentTask(on: date) }
        save(at: instant)
    }

    func toggleTaskPin(_ activity: TaskActivity, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, taskSuggestions.contains(where: { $0.id == activity.id }) else { return }
        synchronize(at: instant, date: date)
        ledger.toggleTaskPin(id: activity.id)
        ledgerDirty = true
        save(at: instant)
    }

    private func rememberCurrentTask(on date: Date) {
        guard !taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ledger.rememberTask(taskName, project: selectedProject ?? .unassigned, date: date)
        ledgerDirty = true
    }

    @ObservationIgnored private var checkpoint: ContinuousClock.Instant?
    @ObservationIgnored private var checkpointDate: Date?
    @ObservationIgnored private var lastSave: ContinuousClock.Instant?
    @ObservationIgnored private var ledgerDirty = false
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var recordingContext: RecordingContext?
    @ObservationIgnored private var recordingSessionID = UUID()
    @ObservationIgnored private let persistence: TimesheetPersistence?
    @ObservationIgnored let calendar: Calendar

    private struct RecordingContext: Equatable {
        let project: FocusProject
        let task: String
        let source: RecordedSession.Source
    }

    init(ledger: TimesheetLedger = TimesheetLedger(), persistence: TimesheetPersistence? = nil, calendar: Calendar = .autoupdatingCurrent, focusDuration: TimeInterval = 1500, breakDuration: TimeInterval = 300, date: Date = .now) {
        var initialLedger = ledger
        var failed = false
        if let persistence {
            do { initialLedger = try persistence.load() }
            catch { failed = true }
        }
        _ = initialLedger.takeChanges()
        self.ledger = initialLedger
        readIndex = WorkspaceReadIndex(ledger: initialLedger)
        self.persistence = persistence
        self.calendar = calendar
        today = calendar.startOfDay(for: date)
        pomodoro = FocusTimer(mode: .pomodoro, focusDuration: focusDuration, breakDuration: breakDuration)
        loadFailed = failed
        if failed { persistenceError = "Couldn’t load your saved workspace. Retry before recording, editing time, or changing projects." }
        if let settings = self.ledger.pomodoroSettings { pomodoro.configure(settings) }
        reconcileProjectSelection()
        if !loadFailed, self.ledger.pomodoroHistoryStartedAt == nil {
            self.ledger.beginPomodoroHistory(at: date)
            ledgerDirty = true
            save()
        }
    }

    func selectProject(_ project: FocusProject?, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard project.map({ !ledger.deletedProjectIDs.contains($0.id) }) ?? true else { return }
        synchronize(at: instant, date: date)
        selectedProject = project.map { ledger.projectMetadata(for: $0) }
        if isRecording(at: instant) { ensureCurrentRow(on: date); rememberCurrentTask(on: date) }
        save(at: instant)
    }

    func setTaskName(_ name: String, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, name != taskName else { return }
        synchronize(at: instant, date: date)
        taskName = String(name.prefix(200))
        if isRecording(at: instant) { rememberCurrentTask(on: date) }
        save(at: instant)
    }

    /// Catalog registration does not invent a Timesheet entry or change the active project.
    func createProject(name: String, accent: FocusProject.Accent, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws -> FocusProject {
        guard canTrack else { throw ProjectCreationError.unavailable }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw ProjectCreationError.invalidName }
        guard accent != .neutral else { throw ProjectCreationError.invalidColor }
        guard !(projects + [.unassigned]).contains(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw ProjectCreationError.duplicateName
        }
        synchronize(at: instant, date: date)
        let project = FocusProject(id: UUID().uuidString, name: name, accent: accent, category: "Personal project")
        ledger.registerProject(project)
        ledgerDirty = true
        save(at: instant)
        return project
    }

    /// Rename/recolor in place. Settle the finishing target before changing its metadata.
    func updateProject(_ project: FocusProject, name: String, accent: FocusProject.Accent,
                       at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw ProjectCreationError.unavailable }
        guard let current = projects.first(where: { $0.id == project.id }) else { throw ProjectCreationError.missing }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw ProjectCreationError.invalidName }
        guard accent != .neutral else { throw ProjectCreationError.invalidColor }
        guard !(projects + [.unassigned]).contains(where: {
            $0.id != current.id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw ProjectCreationError.duplicateName }
        synchronize(at: instant, date: date)
        let edited = FocusProject(id: current.id, name: name, accent: accent, category: current.category)
        ledger.updateProject(edited)
        reconcileProjectSelection()
        if let removal = lastTimesheetRemoval, removal.project.id == edited.id {
            lastTimesheetRemoval = TimesheetRemoval(project: edited, entries: removal.entries, sessions: removal.sessions)
        }
        ledgerDirty = true
        save(at: instant)
    }

    /// Removing a catalog project never erases time. Running timers continue unassigned.
    func deleteProject(_ project: FocusProject, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, projects.contains(where: { $0.id == project.id }) else { return }
        synchronize(at: instant, date: date)
        ledger.deleteProject(id: project.id)
        reconcileProjectSelection()
        if isRecording(at: instant) { ensureCurrentRow(on: date) }
        ledgerDirty = true
        save(at: instant)
    }

    private func reconcileProjectSelection() {
        if let selectedProject {
            self.selectedProject = ledger.deletedProjectIDs.contains(selectedProject.id) ? nil : ledger.projectMetadata(for: selectedProject)
        }
    }

    func play(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        if mode == .pomodoro { pomodoro.play(at: instant) } else { flow.play(at: instant) }
        if isRecording(at: instant) { ensureCurrentRow(on: date); rememberCurrentTask(on: date) }
        save(at: instant)
    }

    /// Launch the current target, including an unnamed target, without resetting running timers.
    func startBothTimers(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        pomodoro.playFocus(at: instant)
        flow.play(at: instant)
        ensureCurrentRow(on: date)
        rememberCurrentTask(on: date)
        save(at: instant)
    }

    /// Assign and start atomically after settling the previous shared task. The other timer is untouched.
    func startTask(_ title: String, timers: TaskTimers, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canTrack, !title.isEmpty else { return }
        synchronize(at: instant, date: date)
        taskName = String(title.prefix(200))
        if timers == .focus || timers == .both { pomodoro.playFocus(at: instant) }
        if timers == .flow || timers == .both { flow.play(at: instant) }
        if isRecording(at: instant) { ensureCurrentRow(on: date); rememberCurrentTask(on: date) }
        save(at: instant)
    }

    func stop(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        synchronize(at: instant, date: date)
        if mode == .pomodoro { pomodoro.stop(at: instant) } else { flow.stop(at: instant) }
        save(at: instant)
    }

    func bothTimersRunning(at instant: ContinuousClock.Instant = .now) -> Bool {
        pomodoro.phase(at: instant) == .running && flow.phase(at: instant) == .running
    }

    /// Settle overlap once, then stop both while preserving elapsed time and the break cycle.
    func stopBothTimers(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        pomodoro.stop(at: instant)
        flow.stop(at: instant)
        save(at: instant)
    }

    func reset(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        synchronize(at: instant, date: date)
        if mode == .pomodoro { pomodoro.reset() } else { flow.reset() }
        save(at: instant)
    }

    func startBreak(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        pomodoro.startBreak(at: instant)
        save(at: instant)
    }

    @discardableResult
    func updatePomodoroSettings(_ settings: PomodoroSettings, at instant: ContinuousClock.Instant = .now, date: Date = .now) -> Bool {
        guard canTrack, settings.isValid else { return false }
        synchronize(at: instant, date: date)
        pomodoro.configure(settings, at: instant)
        ledger.setPomodoroSettings(settings)
        ledgerDirty = true
        save(at: instant)
        return true
    }

    /// Edits replace the settled cell total. Future active time is added to that value.
    func edit(seconds: TimeInterval, project: FocusProject, dayID: String, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, seconds.isFinite, seconds >= 0 else { return }
        synchronize(at: instant, date: date)
        ledger.setSeconds(seconds, project: ledger.projectMetadata(for: project), dayID: dayID)
        ledgerDirty = true
        save(at: instant)
    }

    func editSession(id: String, start: Date, end: Date, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw SessionEditError.unavailable }
        // Validate before settlement, then use the latest duration after settling live time.
        guard let original = ledger.sessions.first(where: { $0.id == id }) else { throw SessionEditError.missing }
        _ = try original.replacingTimes(start: start, end: end)
        synchronize(at: instant, date: date)
        guard let current = ledger.sessions.first(where: { $0.id == id }) else { throw SessionEditError.missing }
        ledger.replaceSession(try current.replacingTimes(start: start, end: end))
        recordingSessionID = UUID()
        ledgerDirty = true
        save(at: instant)
    }

    func deleteSession(id: String, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw SessionEditError.unavailable }
        guard ledger.sessions.contains(where: { $0.id == id }) else { throw SessionEditError.missing }
        synchronize(at: instant, date: date)
        ledger.removeSession(id: id)
        recordingSessionID = UUID()
        ledgerDirty = true
        save(at: instant)
    }

    func addProject(_ project: FocusProject, on date: Date, at instant: ContinuousClock.Instant = .now, now: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: now)
        ledger.ensureEntry(project: ledger.projectMetadata(for: project), on: date, calendar: calendar)
        ledgerDirty = true
        save(at: instant)
    }

    /// Remove only the displayed week's row. Future running time may create it again.
    func removeTimesheetProject(_ project: FocusProject, dayIDs: [String], at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        let removed = ledger.removeEntries(projectID: project.id, dayIDs: dayIDs)
        guard !removed.isEmpty else { return }
        let sessions = ledger.removeSessions(projectID: project.id, dayIDs: dayIDs)
        lastTimesheetRemoval = TimesheetRemoval(project: project, entries: removed, sessions: sessions)
        recordingContext = nil
        ledgerDirty = true
        save(at: instant)
    }

    func undoTimesheetRemoval(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, let removal = lastTimesheetRemoval else { return }
        synchronize(at: instant, date: date)
        ledger.restoreEntries(removal.entries)
        ledger.restoreSessions(removal.sessions)
        lastTimesheetRemoval = nil
        ledgerDirty = true
        save(at: instant)
    }

    /// Clock differences are timing truth; a delayed UI update cannot lose or duplicate time.
    func synchronize(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        displayInstant = instant
        let day = calendar.startOfDay(for: date)
        if day != today { today = day }
        if let checkpoint, let checkpointDate, instant >= checkpoint {
            let components = (instant - checkpoint).components
            let elapsed = max(0, Double(components.seconds) + Double(components.attoseconds) / 1e18)
            let recorded: TimeInterval
            if flow.phase(at: checkpoint) == .running {
                recorded = elapsed
            } else if pomodoro.interval == .focus, pomodoro.phase(at: checkpoint) == .running {
                recorded = min(elapsed, max(0, pomodoro.focusDuration - pomodoro.elapsed(at: checkpoint)))
            } else { recorded = 0 }
            if recorded > 0 {
                let source: RecordedSession.Source = flow.phase(at: checkpoint) == .running ? .flow : .pomodoro
                ledger.record(project: selectedProject ?? .unassigned, from: checkpointDate, seconds: recorded,
                    calendar: calendar, sessionID: recordingSessionID,
                    task: taskName.trimmingCharacters(in: .whitespacesAndNewlines), source: source)
                ledgerDirty = true
            }
        }
        // Resolve the boundary before a caller can change the active target. A delayed
        // refresh uses the previous checkpoint's civil clock, as the recorder does.
        let completionDate = checkpoint.flatMap { previous in
            checkpointDate.map { $0.addingTimeInterval(max(0, pomodoro.intervalDuration - pomodoro.elapsed(at: previous))) }
        } ?? date
        let completion = pomodoro.settleCompletion(at: instant)
        if let completion, completion.interval == .focus {
            ledger.recordCompletion(CompletedPomodoro(id: completion.id, project: selectedProject ?? .unassigned,
                task: taskName.trimmingCharacters(in: .whitespacesAndNewlines), completedAt: completionDate,
                dayID: TimesheetWeek.dayID(for: completionDate, calendar: calendar),
                timeZoneID: calendar.timeZone.identifier, focusDuration: completion.duration))
            ledgerDirty = true
        }
        checkpoint = instant
        checkpointDate = date
        updateRecordingContext(at: instant)
        publishChanges()
        if completion?.interval == .focus { save(at: instant); return }
        if let lastSave, instant - lastSave < .seconds(5) { return }
        save(at: instant)
    }

    func isRecording(at instant: ContinuousClock.Instant = .now) -> Bool {
        flow.phase(at: instant) == .running || (pomodoro.interval == .focus && pomodoro.phase(at: instant) == .running)
    }

    func startUpdating() {
        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled && self != nil {
                self?.synchronize()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { break }
            }
        }
    }

    func shutdown(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        synchronize(at: instant, date: date)
        pomodoro.stop(at: instant)
        flow.stop(at: instant)
        updateTask?.cancel()
        updateTask = nil
        save(at: instant)
    }

    func retryPersistence() {
        if loadFailed, let persistence {
            do {
                ledger = try persistence.load()
                _ = ledger.takeChanges()
                readIndex.rebuild(ledger)
                reconcileProjectSelection()
                if let settings = ledger.pomodoroSettings { pomodoro.configure(settings) }
                if ledger.pomodoroHistoryStartedAt == nil {
                    ledger.beginPomodoroHistory(at: .now)
                    ledgerDirty = true
                }
                loadFailed = false
                persistenceError = nil
                save()
            } catch { return }
        } else { save() }
    }

    private func ensureCurrentRow(on date: Date) {
        ledger.ensureEntry(project: selectedProject ?? .unassigned, on: date, calendar: calendar)
        ledgerDirty = true
    }

    private func publishChanges() {
        let changes = ledger.takeChanges()
        readIndex.apply(changes, ledger: ledger)
    }

    private func save(at instant: ContinuousClock.Instant = .now) {
        updateRecordingContext(at: instant)
        publishChanges()
        guard !loadFailed, ledgerDirty, let persistence else { return }
        do {
            try persistence.save(ledger)
            ledgerDirty = false
            lastSave = instant
            persistenceError = nil
        } catch { persistenceError = "Couldn’t save your changes. Retry to keep them on this Mac." }
    }

    private func updateRecordingContext(at instant: ContinuousClock.Instant) {
        let source: RecordedSession.Source?
        if flow.phase(at: instant) == .running { source = .flow }
        else if pomodoro.interval == .focus, pomodoro.phase(at: instant) == .running { source = .pomodoro }
        else { source = nil }
        let context = source.map { RecordingContext(project: selectedProject ?? .unassigned,
            task: taskName.trimmingCharacters(in: .whitespacesAndNewlines), source: $0) }
        if context != recordingContext { recordingSessionID = UUID(); recordingContext = context }
    }
}
