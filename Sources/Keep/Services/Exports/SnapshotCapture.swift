import Foundation

/// One synchronous checkpoint shared by backup and reporting. No await between store copies.
struct SnapshotCapture {
    enum Requirement { case workspace, stats, backup }
    let workspace: WorkspaceModel
    let tasks: DailyTaskStore
    let habits: HabitStore
    let preferences: AppPreferences
    var gate: BackupRestoreGate?

    func capture(_ requirement: Requirement, at instant: ContinuousClock.Instant = .now, date: Date = .now) throws -> PersistentSnapshot {
        guard gate?.isLocked != true else { throw ExportFailure.restoreLocked }
        let all = requirement != .workspace
        guard !all || (tasks.canEdit && habits.canEdit && preferences.canEdit &&
            tasks.persistenceError == nil && habits.persistenceError == nil && preferences.persistenceError == nil)
        else { throw ExportFailure.unavailable }
        let ledger: TimesheetLedger
        do { ledger = try workspace.capturePersistentData(at: instant, date: date) }
        catch { throw ExportFailure.unavailable }
        return PersistentSnapshot(workspace: ledger, tasks: all ? tasks.archive : nil, habits: all ? habits.archive : nil,
            settings: all ? PortableSettings(preferences.snapshot) : nil,
            projects: projects, capturedAt: date, calendar: StatsSnapshot.calendar(workspace.calendar))
    }

    var projects: [StatsInput.Project] {
        _ = workspace.readIndex.metadataRevision
        var catalog = Dictionary(uniqueKeysWithValues: workspace.readIndex.statsProjects.map { ($0.id, $0) })
        for project in workspace.ledger.catalogProjects + [.unassigned] {
            catalog[project.id] = .init(id: project.id, name: project.name, accent: project.accent.rawValue,
                                      deleted: workspace.ledger.deletedProjectIDs.contains(project.id))
        }
        return catalog.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func retry() {
        guard gate?.isLocked != true else { return }
        workspace.retryPersistence(); tasks.retryPersistence(); habits.retryPersistence(); preferences.retryPersistence()
    }
}
