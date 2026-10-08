import Foundation

/// Value archives copied together on the main actor, then used only by background work.
nonisolated struct PersistentSnapshot: Sendable {
    let workspace: TimesheetLedger
    let tasks: TaskArchive?
    let habits: HabitArchive?
    let settings: PortableSettings?
    let projects: [StatsInput.Project]
    let capturedAt: Date
    let calendar: Calendar

    func backupPayload() throws -> BackupPayload {
        guard let tasks, let habits, let settings else { throw BackupFailure.localDataUnavailable }
        return BackupPayload(workspace: workspace, tasks: tasks, habits: habits, settings: settings)
    }
}

nonisolated enum ExportData: String, CaseIterable, Sendable {
    case calendar = "Calendar", timesheet = "Timesheet", stats = "Stats"
    var format: String { self == .stats ? "CSV reports (.zip)" : "CSV (.csv)" }
    var fileExtension: String { self == .stats ? "zip" : "csv" }
}

nonisolated struct ExportRequest: Sendable {
    let data: ExportData
    let from: Date
    let through: Date
    let projectID: String?
    let taskKeys: Set<String>?

    func query() -> StatsQuery {
        StatsQuery(period: .custom, customStart: from, customEnd: through,
                   projectID: projectID, taskKeys: data == .timesheet ? nil : taskKeys)
    }
    func validate(now: Date, calendar: Calendar) throws {
        guard from.timeIntervalSince1970.isFinite, through.timeIntervalSince1970.isFinite,
              calendar.startOfDay(for: from) <= calendar.startOfDay(for: through),
              calendar.startOfDay(for: through) <= calendar.startOfDay(for: now),
              taskKeys == nil || (data != .timesheet && projectID != nil && taskKeys?.isEmpty == false) else { throw ExportFailure.invalidRequest }
    }
    func filename(calendar: Calendar) -> String {
        "Keep-\(data.rawValue)-\(StatsSnapshot.dayID(from, calendar: calendar))-to-\(StatsSnapshot.dayID(through, calendar: calendar)).\(data.fileExtension)"
    }
}

nonisolated struct ExportReport: Sendable {
    let filename: String
    let contents: Data
}

nonisolated struct ExportArtifact: Sendable {
    let root: URL
    let url: URL
    let filename: String
}

nonisolated enum ExportFailure: LocalizedError {
    case invalidRequest, unavailable, restoreLocked, noWindow, saveFailed
    var errorDescription: String? {
        switch self {
        case .invalidRequest: "Choose From on or before Through, no later than today. Select a project before filtering tasks."
        case .unavailable: "Required saved data is unavailable. Use Retry to reload or save it, then export again."
        case .restoreLocked: "Wait for restore recovery to finish before exporting."
        case .noWindow: "Open a Keep window and try Export again."
        case .saveFailed: "Couldn’t save the export. Check folder access and available disk space, then try again."
        }
    }
}
