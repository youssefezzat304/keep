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
    private(set) var lastTimesheetRemoval: TimesheetRemoval?
    var canTrack: Bool { !loadFailed }
    var projects: [FocusProject] { (FocusProject.defaults + ledger.customProjects).filter { !ledger.deletedProjectIDs.contains($0.id) } }
    var pomodoroSettings: PomodoroSettings { ledger.pomodoroSettings ?? .defaults }

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
        self.ledger = ledger
        self.persistence = persistence
        self.calendar = calendar
        today = calendar.startOfDay(for: date)
        pomodoro = FocusTimer(mode: .pomodoro, focusDuration: focusDuration, breakDuration: breakDuration)
        if let persistence {
            do { self.ledger = try persistence.load() }
            catch {
                loadFailed = true
                persistenceError = "Couldn’t load your saved workspace. Retry before recording, editing time, or changing projects."
            }
        }
        if let settings = self.ledger.pomodoroSettings { pomodoro.configure(settings) }
        reconcileProjectSelection()
    }

    func selectProject(_ project: FocusProject?, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard project.map({ !ledger.deletedProjectIDs.contains($0.id) }) ?? true else { return }
        synchronize(at: instant, date: date)
        selectedProject = project
        if isRecording(at: instant) { ensureCurrentRow(on: date) }
        save(at: instant)
    }

    func setTaskName(_ name: String, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, name != taskName else { return }
        synchronize(at: instant, date: date)
        taskName = String(name.prefix(200))
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
        if let selectedProject, ledger.deletedProjectIDs.contains(selectedProject.id) { self.selectedProject = nil }
    }

    func play(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        if mode == .pomodoro { pomodoro.play(at: instant) } else { flow.play(at: instant) }
        if isRecording(at: instant) { ensureCurrentRow(on: date) }
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
        if isRecording(at: instant) { ensureCurrentRow(on: date) }
        save(at: instant)
    }

    func stop(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        synchronize(at: instant, date: date)
        if mode == .pomodoro { pomodoro.stop(at: instant) } else { flow.stop(at: instant) }
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
        ledger.setSeconds(seconds, project: project, dayID: dayID)
        ledgerDirty = true
        save(at: instant)
    }

    func addProject(_ project: FocusProject, on date: Date, at instant: ContinuousClock.Instant = .now, now: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: now)
        ledger.ensureEntry(project: project, on: date, calendar: calendar)
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
        pomodoro.settleCompletion(at: instant)
        checkpoint = instant
        checkpointDate = date
        updateRecordingContext(at: instant)
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
                reconcileProjectSelection()
                if let settings = ledger.pomodoroSettings { pomodoro.configure(settings) }
                loadFailed = false
                persistenceError = nil
            } catch { return }
        } else { save() }
    }

    private func ensureCurrentRow(on date: Date) {
        ledger.ensureEntry(project: selectedProject ?? .unassigned, on: date, calendar: calendar)
        ledgerDirty = true
    }

    private func save(at instant: ContinuousClock.Instant = .now) {
        updateRecordingContext(at: instant)
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
