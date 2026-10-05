import Foundation
import Observation

/// Shared across windows and tabs. All timer actions settle the single recorder first.
@Observable
final class WorkspaceModel {
    private(set) var pomodoro = FocusTimer(mode: .pomodoro)
    private(set) var flow = FocusTimer(mode: .flow)
    private(set) var selectedProject: FocusProject? = FocusProject.defaults.first
    private(set) var ledger: TimesheetLedger
    private(set) var persistenceError: String?
    private(set) var loadFailed = false
    private(set) var today: Date
    var canTrack: Bool { !loadFailed }

    @ObservationIgnored private var checkpoint: ContinuousClock.Instant?
    @ObservationIgnored private var checkpointDate: Date?
    @ObservationIgnored private var lastSave: ContinuousClock.Instant?
    @ObservationIgnored private var ledgerDirty = false
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private let persistence: TimesheetPersistence?
    @ObservationIgnored let calendar: Calendar

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
                persistenceError = "Couldn’t load your saved time. Retry before recording or editing entries."
            }
        }
    }

    func selectProject(_ project: FocusProject?, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        synchronize(at: instant, date: date)
        selectedProject = project
        if isRecording(at: instant) { ensureCurrentRow(on: date) }
        save(at: instant)
    }

    func play(_ mode: FocusTimer.Mode, at instant: ContinuousClock.Instant = .now, date: Date = .now) {
        guard canTrack else { return }
        synchronize(at: instant, date: date)
        if mode == .pomodoro { pomodoro.play(at: instant) } else { flow.play(at: instant) }
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
                ledger.record(project: selectedProject ?? .unassigned, from: checkpointDate, seconds: recorded, calendar: calendar)
                ledgerDirty = true
            }
        }
        if pomodoro.phase(at: instant) == .completed { pomodoro.stop(at: instant) }
        checkpoint = instant
        checkpointDate = date
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
        guard !loadFailed, ledgerDirty, let persistence else { return }
        do {
            try persistence.save(ledger)
            ledgerDirty = false
            lastSave = instant
            persistenceError = nil
        } catch { persistenceError = "Couldn’t save your time. Retry to keep the latest entries on this Mac." }
    }
}
