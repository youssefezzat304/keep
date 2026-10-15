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
    private(set) var taskReference: TaskReference?
    private(set) var habitNameExtension: String?
    private(set) var ledger: TimesheetLedger
    private(set) var persistenceError: String?
    private(set) var loadFailed = false
    private(set) var today: Date
    /// Lets the status item use the workspace refresh without owning another timeline.
    private(set) var displayInstant = ContinuousClock.now
    private(set) var pomodoroCompletion: PomodoroCompletionNotice?
    private(set) var lastTimesheetRemoval: TimesheetRemoval?
    var canTrack: Bool { !loadFailed && persistence?.access?.isLocked != true }
    let readIndex: WorkspaceReadIndex
    var projects: [FocusProject] { _ = readIndex.metadataRevision; return readIndex.activeProjects }
    var pomodoroSettings: PomodoroSettings { ledger.pomodoroSettings ?? .defaults }
    var pomodoroPresets: [PomodoroPreset] { ledger.pomodoroPresets }
    var activeHabit: Habit? {
        guard case .habit(let id) = taskReference else { return nil }
        return habits?.habits.first { $0.id == id }
    }
    var activeTaskName: String {
        if let habit = activeHabit { return String(HabitTaskName.title(habit.name, extension: habitNameExtension).prefix(200)) }
        return linkedTitle(taskReference) ?? taskName
    }
    var taskSuggestions: [TaskActivity] { _ = readIndex.metadataRevision; return readIndex.suggestions }

    func capturePersistentData(at instant: ContinuousClock.Instant = .now, date: Date = .now) throws -> TimesheetLedger {
        guard canTrack else { throw BackupFailure.localDataUnavailable }
        synchronize(at: instant, date: date)
        save(at: instant)
        guard persistenceError == nil else { throw BackupFailure.localDataUnavailable }
        return ledger
    }

    func installBackup(_ value: TimesheetLedger) {
        ledger = value; _ = ledger.takeChanges()
        readIndex.rebuild(ledger)
        pomodoroCompletion = nil
        pomodoro = FocusTimer(mode: .pomodoro); flow = FocusTimer(mode: .flow)
        pomodoro.configure(value.pomodoroSettings ?? .defaults)
        selectedProject = nil; taskName = ""; taskReference = nil; lastTimesheetRemoval = nil
        habitNameExtension = nil
        recordingContext = nil; recordingSessionID = UUID(); checkpoint = nil; checkpointDate = nil
        ledgerDirty = false; loadFailed = false; persistenceError = nil; lastSave = nil
        refreshHabitProgress()
    }

    func selectTask(_ activity: TaskActivity, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, let current = taskSuggestions.first(where: { $0.id == activity.id }) else { return }
        synchronize(at: instant, date: date)
        taskReference = validReference(current.taskReference)
        habitNameExtension = activeHabit == nil ? nil : current.habitNameExtension
        if case .habit = taskReference { selectedProject = ledger.ensureHabitsProject(); ledgerDirty = true }
        else { selectedProject = projects.first { $0.id == current.project.id } }
        taskName = String((linkedTitle(taskReference) ?? current.title).prefix(200))
        taskName = activeTaskName
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
        guard !activeTaskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ledger.rememberTask(activeTaskName, project: selectedProject ?? .unassigned, date: date, reference: taskReference, habitNameExtension: habitNameExtension)
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
    @ObservationIgnored private let tasks: DailyTaskStore?
    @ObservationIgnored private let habits: HabitStore?
    @ObservationIgnored private let timerPreferences: AppPreferences?
    @ObservationIgnored var onTimerReminder: ((TimerSound) -> Void)?
    @ObservationIgnored private var flowReminders = FlowReminderSchedule()
    @ObservationIgnored let calendar: Calendar

    private struct RecordingContext: Equatable {
        let project: FocusProject
        let task: String
        let source: RecordedSession.Source
        let reference: TaskReference?
    }

    init(ledger: TimesheetLedger = TimesheetLedger(), persistence: TimesheetPersistence? = nil, calendar: Calendar = .autoupdatingCurrent, focusDuration: TimeInterval = 1500, breakDuration: TimeInterval = 300, date: Date = .now, timerPreferences: AppPreferences? = nil, tasks: DailyTaskStore? = nil, habits: HabitStore? = nil) {
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
        self.timerPreferences = timerPreferences
        self.tasks = tasks
        self.habits = habits
        var recordingCalendar = Calendar(identifier: .gregorian)
        recordingCalendar.timeZone = calendar.timeZone
        recordingCalendar.locale = calendar.locale
        recordingCalendar.firstWeekday = calendar.firstWeekday
        self.calendar = recordingCalendar
        today = recordingCalendar.startOfDay(for: date)
        pomodoro = FocusTimer(mode: .pomodoro, focusDuration: focusDuration, breakDuration: breakDuration)
        loadFailed = failed
        if failed { persistenceError = "Couldn’t load your saved workspace. Retry before recording, editing time, or changing projects." }
        if let settings = self.ledger.pomodoroSettings { pomodoro.configure(settings) }
        reconcileProjectSelection()
        habits?.beforeManualEdit = { [weak self] in self?.synchronize() }
        habits?.onReload = { [weak self] in self?.refreshHabitProgress() }
        habits?.retryRecordedData = { [weak self] in self?.retryPersistence() }
        refreshHabitProgress()
        if !loadFailed, self.ledger.pomodoroHistoryStartedAt == nil {
            self.ledger.beginPomodoroHistory(at: date)
            ledgerDirty = true
            save()
        }
    }

    func selectProject(_ project: FocusProject?, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
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
        taskReference = nil
        habitNameExtension = nil
        if isRecording(at: instant) { rememberCurrentTask(on: date) }
        save(at: instant)
    }

    func setHabitNameExtension(_ detail: String, habitID: UUID, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack, habits?.canEdit == true else { throw HabitTaskNameError.unavailable }
        guard let habit = activeHabit, habit.id == habitID else { throw HabitTaskNameError.changedHabit }
        let detail = HabitTaskName.normalizedExtension(detail)
        let title = HabitTaskName.title(habit.name, extension: detail)
        guard title.count <= 200 else { throw HabitTaskNameError.tooLong }
        guard detail != habitNameExtension else { return }
        synchronize(at: instant, date: date)
        habitNameExtension = detail
        taskName = title
        rememberCurrentTask(on: date)
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

    var projectTargets: [String: WeeklyTargets] { ledger.projectTargets }

    func updateProjectTargets(projectID: String, targets: WeeklyTargets?, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw ProjectCreationError.unavailable }
        guard projects.contains(where: { $0.id == projectID }) else { throw ProjectCreationError.missing }
        guard targets?.isValid(maximum: WeeklyTargets.maximumMinutes) != false else { throw WeeklyTargetsError.invalidTime }
        synchronize(at: instant, date: date)
        ledger.setProjectTargets(targets, projectID: projectID)
        ledgerDirty = true
        save(at: instant)
    }

    func weeklyProjectSeconds(projectID: String, today: Date = .now) -> Double {
        _ = readIndex.revision
        let days = TimesheetWeek(containing: today, calendar: calendar).days.filter { $0.date <= today }.map(\.id)
        return readIndex.entries(on: days).filter { $0.project.id == projectID }.reduce(0) { $0 + $1.seconds }
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
    func startTask(_ title: String, timers: TaskTimers, at instant: ContinuousClock.Instant = .now, date: Date = .now, reference: TaskReference? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canTrack, !title.isEmpty else { return }
        synchronize(at: instant, date: date)
        taskReference = validReference(reference)
        habitNameExtension = nil
        if case .habit = taskReference { selectedProject = ledger.ensureHabitsProject(); ledgerDirty = true }
        taskName = String((linkedTitle(taskReference) ?? title).prefix(200))
        if timers == .focus || timers == .both { pomodoro.playFocus(at: instant) }
        if timers == .flow || timers == .both { flow.play(at: instant) }
        if isRecording(at: instant) { ensureCurrentRow(on: date); rememberCurrentTask(on: date) }
        save(at: instant)
    }

    func startTask(_ task: FocusTask, on day: String, timers: TaskTimers, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard day == TaskDay.id(for: date, calendar: calendar) else { return }
        let reference: TaskReference = task.habitID.map { .habit(id: $0) } ?? .task(id: task.id, dayID: day)
        guard validReference(reference) != nil else { return }
        startTask(task.title, timers: timers, at: instant, date: date, reference: reference)
    }

    func editTask(id: UUID, on day: String, title: String, estimateMinutes: Int?, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack, let tasks else { throw TaskEditError.unavailable }
        synchronize(at: instant, date: date)
        try tasks.update(taskID: id, on: day, title: title, estimateMinutes: estimateMinutes)
        if taskReference == .task(id: id, dayID: day) {
            taskName = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            if isRecording(at: instant) { rememberCurrentTask(on: date) }
            save(at: instant)
        }
    }

    func removeTask(_ task: FocusTask, on day: String, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, let tasks else { return }
        synchronize(at: instant, date: date)
        tasks.remove(taskID: task.id, on: day, habitID: task.habitID)
        if task.habitID == nil, taskReference == .task(id: task.id, dayID: day) { taskReference = nil }
        save(at: instant)
    }

    private func linkedTitle(_ reference: TaskReference?) -> String? {
        switch reference {
        case .task(let id, let day): tasks?.archive.days[day]?.first { $0.id == id }?.title
        case .habit(let id): habits?.habits.first { $0.id == id }?.name
        case nil: nil
        }
    }

    private func validReference(_ reference: TaskReference?) -> TaskReference? {
        guard let reference, reference.isValid else { return nil }
        switch reference {
        case .task(let id, let day):
            return tasks?.canEdit == true && tasks?.archive.days[day]?.contains(where: { $0.id == id }) == true ? reference : nil
        case .habit(let id): return habits?.canEdit == true && habits?.habits.contains(where: { $0.id == id }) == true ? reference : nil
        }
    }

    private func refreshHabitProgress(live: Bool = false) {
        habits?.recordedDataAvailable = !loadFailed
        guard !loadFailed else { return }
        let due = habits?.applyRecordedProgress(readIndex.taskTimes.habits, live: live) == true
        if due && timerPreferences?.canEdit == true && timerPreferences?.timerSoundsEnabled == true {
            onTimerReminder?(.habitComplete)
        }
    }

    func stop(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
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
        guard canTrack else { return }
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

    func dismissPomodoroCompletion() { pomodoroCompletion = nil }

    /// Leaving a break starts focus without resetting the completed-focus cycle or Flow.
    func skipPomodoroBreak(at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, pomodoro.interval == .rest else { return }
        synchronize(at: instant, date: date)
        pomodoro.playFocus(at: instant)
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

    func savePomodoroPreset(name: String, settings: PomodoroSettings, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw PomodoroPresetError.unavailable }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= PomodoroPreset.maximumNameLength else { throw PomodoroPresetError.invalidName }
        guard settings.isValid else { throw PomodoroPresetError.invalidSettings }
        let preset = PomodoroPreset(id: UUID(), name: name, settings: settings)
        guard !pomodoroPresets.contains(where: { $0.nameKey == preset.nameKey }) else { throw PomodoroPresetError.duplicateName }
        synchronize(at: instant, date: date)
        ledger.addPomodoroPreset(preset)
        ledgerDirty = true
        save(at: instant)
        guard persistenceError == nil else { throw PomodoroPresetError.saveFailed }
    }

    func removePomodoroPreset(id: UUID, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw PomodoroPresetError.unavailable }
        guard pomodoroPresets.contains(where: { $0.id == id }) else { throw PomodoroPresetError.missing }
        synchronize(at: instant, date: date)
        ledger.removePomodoroPreset(id: id)
        ledgerDirty = true
        save(at: instant)
        guard persistenceError == nil else { throw PomodoroPresetError.saveFailed }
    }

    /// Edits replace the settled cell total. Future active time is added to that value.
    func edit(seconds: TimeInterval, project: FocusProject, dayID: String, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack, seconds.isFinite, seconds >= 0 else { return }
        synchronize(at: instant, date: date)
        ledger.setSeconds(seconds, project: ledger.projectMetadata(for: project), dayID: dayID)
        ledgerDirty = true
        save(at: instant)
    }

    func entryTasks(on date: Date) -> [FocusTask] {
        guard tasks?.canEdit == true else { return [] }
        return tasks?.tasks(on: TaskDay.id(for: date, calendar: calendar)) ?? []
    }

    func entryTaskSuggestions(on date: Date, projectID: String) -> [CalendarEntryTaskSuggestion] {
        let day = TaskDay.id(for: date, calendar: calendar)
        let saved = entryTasks(on: date)
        var suggestions: [CalendarEntryTaskSuggestion] = saved.map { task in
            let reference: TaskReference = task.habitID.map { .habit(id: $0) } ?? .task(id: task.id, dayID: day)
            var detail = task.habitID == nil ? "Task" : "Habit"
            if let minutes = task.estimateMinutes { detail += " · \(minutes) min" }
            if saved.filter({ StatsQuery.taskKey($0.title) == StatsQuery.taskKey(task.title) }).count > 1 {
                detail += " · " + String(task.id.uuidString.prefix(8))
            }
            return .init(id: reference.storageKey, title: task.title, detail: detail, reference: reference)
        }
        var references = Set(suggestions.compactMap(\.reference))
        var names = Set(suggestions.map { StatsQuery.taskKey($0.title) })
        for recent in taskSuggestions where recent.project.id == projectID {
            let reference = validReference(recent.taskReference)
            if let reference {
                guard references.insert(reference).inserted else { continue }
            } else {
                guard names.insert(StatsQuery.taskKey(recent.title)).inserted else { continue }
            }
            let title = linkedTitle(reference) ?? recent.title
            let detail: String
            switch reference {
            case .task(_, let plannedDay): detail = "Task · " + plannedDay
            case .habit: detail = "Habit"
            case nil: detail = "Recent task"
            }
            suggestions.append(.init(id: "recent/" + recent.id.uuidString, title: title, detail: detail, reference: reference))
            names.insert(StatsQuery.taskKey(title))
        }
        for title in readIndex.names(projectID: projectID).values.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            guard !title.isEmpty, names.insert(StatsQuery.taskKey(title)).inserted else { continue }
            suggestions.append(.init(id: "name/" + StatsQuery.taskKey(title), title: title, detail: "Recorded task", reference: nil))
        }
        return suggestions
    }

    /// Added work shares the session ledger and all derived reports, without changing timer targets.
    @discardableResult
    func addCalendarEntry(_ draft: CalendarEntryDraft, at instant: ContinuousClock.Instant = .now, now: Date = .now) throws -> RecordedSession {
        guard canTrack else { throw SessionEditError.unavailable }
        let project: FocusProject
        if draft.projectID == FocusProject.unassigned.id { project = .unassigned }
        else if let existing = projects.first(where: { $0.id == draft.projectID }) { project = existing }
        else { throw CalendarEntryError.missingProject }
        if let reference = draft.reference, validReference(reference) == nil { throw CalendarEntryError.missingTask }
        let entry = try draft.session(project: project, calendar: calendar, now: now)
        synchronize(at: instant, date: now)
        var candidate = ledger
        candidate.record(project: project, from: entry.start, seconds: entry.seconds, calendar: calendar,
            sessionID: entry.recordingID, task: entry.task, source: .manual, taskReference: entry.taskReference)
        // Persist before publishing so retrying a failed addition cannot duplicate the entry.
        do { try persistence?.save(candidate) }
        catch { throw CalendarEntryError.saveFailed }
        ledger = candidate
        ledgerDirty = persistence == nil
        persistenceError = nil
        save(at: instant)
        guard let saved = ledger.sessions.first(where: { $0.recordingID == entry.recordingID }) else { throw SessionEditError.missing }
        return saved
    }

    func editSession(id: String, start: Date? = nil, end: Date? = nil, task: String? = nil, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws {
        guard canTrack else { throw SessionEditError.unavailable }
        // Validate before settlement, then use the latest duration after settling live time.
        guard let original = ledger.sessions.first(where: { $0.id == id }) else { throw SessionEditError.missing }
        _ = try original.replacing(start: start ?? original.start, end: end ?? original.end, task: task)
        synchronize(at: instant, date: date)
        guard let current = ledger.sessions.first(where: { $0.id == id }) else { throw SessionEditError.missing }
        ledger.replaceSession(try current.replacing(start: start ?? current.start, end: end ?? current.end, task: task))
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
                    task: taskName.trimmingCharacters(in: .whitespacesAndNewlines), source: source, taskReference: taskReference)
                ledgerDirty = true
            }
        }
        // Resolve the boundary before a caller can change the active target. A delayed
        // refresh uses the previous checkpoint's civil clock, as the recorder does.
        let completionDate = checkpoint.flatMap { previous in
            checkpointDate.map { $0.addingTimeInterval(max(0, pomodoro.intervalDuration - pomodoro.elapsed(at: previous))) }
        } ?? date
        let completion = pomodoro.settleCompletion(at: instant)
        if let completion {
            pomodoroCompletion = .init(intervalID: completion.id, isBreak: completion.interval == .rest)
        }
        let flowReminderDue = flowReminders.isDue(timer: flow, minutes: timerPreferences?.flowReminderMinutes, at: instant)
        if timerPreferences?.canEdit == true && timerPreferences?.timerSoundsEnabled == true {
            if let completion {
                onTimerReminder?(completion.interval == .focus ? .focusComplete : .breakComplete)
            }
            if flowReminderDue { onTimerReminder?(.flowReminder) }
        }
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
        publishChanges(live: true)
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
        guard persistence?.access?.isLocked != true else { return }
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

    private func publishChanges(live: Bool = false) {
        let changes = ledger.takeChanges()
        readIndex.apply(changes, ledger: ledger)
        refreshHabitProgress(live: live)
    }

    private func save(at instant: ContinuousClock.Instant = .now) {
        if let notice = pomodoroCompletion,
           pomodoro.phase(at: instant) != .completed || notice.intervalID != pomodoro.intervalID || notice.isBreak != (pomodoro.interval == .rest) {
            pomodoroCompletion = nil
        }
        updateRecordingContext(at: instant)
        publishChanges()
        guard canTrack, ledgerDirty, let persistence else { return }
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
            task: taskName.trimmingCharacters(in: .whitespacesAndNewlines), source: $0, reference: taskReference) }
        if context != recordingContext { recordingSessionID = UUID(); recordingContext = context }
    }
}
