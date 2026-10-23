import Foundation

/// An explicit allowlist: workspace settings can never leak into a portable data file.
nonisolated struct TrackedWorkspace: Codable, Equatable, Sendable {
    var entries: [TimesheetEntry]
    var customProjects: [FocusProject]
    var projectOverrides: [FocusProject]
    var projectTargets: [String: WeeklyTargets]
    var deletedProjectIDs: Set<String>
    var sessions: [RecordedSession]
    var taskActivities: [TaskActivity]
    var completedPomodoros: [CompletedPomodoro]
    var pomodoroHistoryStartedAt: Date?

    init(_ ledger: TimesheetLedger) {
        entries = ledger.entries; customProjects = ledger.customProjects; projectOverrides = ledger.projectOverrides
        projectTargets = ledger.projectTargets; deletedProjectIDs = ledger.deletedProjectIDs
        sessions = ledger.sessions; taskActivities = ledger.taskActivities; completedPomodoros = ledger.completedPomodoros
        pomodoroHistoryStartedAt = ledger.pomodoroHistoryStartedAt
    }
    var projects: [FocusProject] {
        FocusProject.defaults.map { original in projectOverrides.first { $0.id == original.id } ?? original } + customProjects
    }
}

nonisolated struct KeepDataPayload: Codable, Equatable, Sendable {
    var workspace: TrackedWorkspace
    var tasks: TaskArchive
    var habits: HabitArchive
    var weeklyFocusGoalMinutes: Int?
    var channels: [MusicChannel]
    var reportingTimeZone: String

    init(_ snapshot: PersistentSnapshot) throws {
        guard let tasks = snapshot.tasks, let habits = snapshot.habits, let settings = snapshot.settings else { throw ExportFailure.unavailable }
        self.workspace = TrackedWorkspace(snapshot.workspace); self.tasks = tasks; self.habits = habits
        weeklyFocusGoalMinutes = settings.weeklyFocusGoalMinutes; channels = settings.channels
        reportingTimeZone = snapshot.calendar.timeZone.identifier
    }

    init(backup: BackupPayload, timeZone: String) {
        workspace = TrackedWorkspace(backup.workspace); tasks = backup.tasks; habits = backup.habits
        weeklyFocusGoalMinutes = backup.settings.weeklyFocusGoalMinutes; channels = backup.settings.channels
        reportingTimeZone = timeZone
    }

    func validate() throws {
        try TimesheetPersistence.validate(TimesheetLedger(tracked: workspace))
        try TaskPersistence.validate(tasks)
        guard habits.isValid, TimeZone(identifier: reportingTimeZone) != nil,
              weeklyFocusGoalMinutes.map({ (1...10080).contains($0) }) ?? true,
              channels.allSatisfy(\.isValid), Set(channels.map(\.id)).count == channels.count,
              workspace.entries.allSatisfy({ TaskDay.isValid($0.dayID) }) else { throw ImportFailure.invalidArchive }
        // Historical orphan references are valid after task/habit deletion. If a definition
        // is present, however, its identity and the saved record must remain unambiguous.
        let names = TimesheetLedger(tracked: workspace).catalogProjects.filter { !workspace.deletedProjectIDs.contains($0.id) }.map(\.name)
        guard Set(names.map(ImportMerge.nameKey)).count == names.count,
              Set(habits.habits.map { ImportMerge.nameKey($0.name) }).count == habits.habits.count else { throw ImportFailure.invalidArchive }
    }

    func applyingContent(to settings: SettingsArchive) -> SettingsArchive {
        var result = settings
        result.weeklyFocusGoalMinutes = weeklyFocusGoalMinutes; result.channels = channels
        return result
    }
}

nonisolated struct KeepDataEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String
    let payload: Data
    let checksum: String

    init(_ data: KeepDataPayload, date: Date, appVersion: String) throws {
        try data.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        payload = try encoder.encode(data)
        guard payload.count <= BackupEnvelope.maximumBytes / 2 else { throw BackupFailure.tooLarge }
        schemaVersion = 1; createdAt = date; self.appVersion = appVersion
        checksum = BackupEnvelope.digest(payload)
    }

    func validatedPayload() throws -> KeepDataPayload {
        guard schemaVersion == 1 else { throw ImportFailure.unsupportedVersion }
        guard createdAt.timeIntervalSince1970.isFinite, createdAt >= .distantPast, createdAt <= .distantFuture,
              !appVersion.isEmpty, appVersion.count <= 100, payload.count <= BackupEnvelope.maximumBytes / 2,
              checksum == BackupEnvelope.digest(payload) else { throw ImportFailure.invalidArchive }
        let value = try JSONDecoder().decode(KeepDataPayload.self, from: payload)
        try value.validate()
        return value
    }

    static func decode(_ bytes: Data) throws -> KeepDataPayload {
        guard bytes.count <= BackupEnvelope.maximumBytes else { throw BackupFailure.tooLarge }
        return try JSONDecoder().decode(Self.self, from: bytes).validatedPayload()
    }
}

nonisolated enum ImportFailure: LocalizedError {
    case invalidArchive, unsupportedVersion, unsupportedFile, invalidRange, unavailable, backupFailed
    var errorDescription: String? {
        switch self {
        case .invalidArchive: "This file is damaged or contains invalid data. Choose another Keep archive."
        case .unsupportedVersion: "This file needs a different version of Keep. Update Keep and try again."
        case .unsupportedFile: "Choose a Keep data archive (.keepdata) or Keep backup (.keepbackup). CSV reports cannot be imported."
        case .invalidRange: "Choose a valid From date on or before Through."
        case .unavailable: "Wait for backup or recovery to finish, and resolve any saved-data errors before importing."
        case .backupFailed: "Keep couldn’t save and verify the recovery file. No imported data was written. Check disk space and folder access, then retry."
        }
    }
}
