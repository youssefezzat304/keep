import Foundation

protocol ImportProcessing: Actor {
    func open(_ url: URL, timeZone: String) async throws -> KeepDataPayload
    func review(source: KeepDataPayload, local: KeepDataPayload, scope: ImportScope, decisions: ImportDecisions) async throws -> ImportReview
    func saveRecovery(_ payload: KeepDataPayload, date: Date) async throws -> URL
    func candidateBytes(_ payload: KeepDataPayload, workspace: TimesheetLedger, settings: SettingsArchive) async throws -> [String: Data]
}

actor ImportFiles: ImportProcessing {
    let disk: any BackupFileStorage
    let appVersion: String
    init(disk: any BackupFileStorage = BackupLocalFiles(root: BackupLocalFiles.applicationRoot), appVersion: String = "1.0") {
        self.disk = disk; self.appVersion = appVersion
    }
    func open(_ url: URL, timeZone: String) async throws -> KeepDataPayload {
        guard ["keepdata", "keepbackup"].contains(url.pathExtension.lowercased()) else { throw ImportFailure.unsupportedFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bytes = try await disk.read(url)
        try Task.checkCancellation()
        do {
            switch url.pathExtension.lowercased() {
            case "keepdata": return try KeepDataEnvelope.decode(bytes)
            case "keepbackup":
                let payload = try KeepDataPayload(backup: BackupEnvelope.decode(bytes).validatedPayload(), timeZone: timeZone)
                try payload.validate(); return payload
            default: throw ImportFailure.invalidArchive
            }
        } catch let error as ImportFailure { throw error }
        catch let error as BackupFailure { throw error }
        catch { throw ImportFailure.invalidArchive }
    }
    func review(source: KeepDataPayload, local: KeepDataPayload, scope: ImportScope, decisions: ImportDecisions) throws -> ImportReview {
        try Task.checkCancellation()
        let value = try ImportMerge.review(source: source, local: local, scope: scope, decisions: decisions)
        try Task.checkCancellation(); return value
    }
    func saveRecovery(_ payload: KeepDataPayload, date: Date) async throws -> URL {
        do {
            let envelope = try KeepDataEnvelope(payload, date: date, appVersion: appVersion)
            let bytes = try await disk.encode(envelope)
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .gmt; formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let url = disk.root.appendingPathComponent("ImportRecovery", isDirectory: true)
                .appendingPathComponent("Keep-Before-Import-\(formatter.string(from: date))-\(UUID().uuidString).keepdata")
            try await disk.write(bytes, to: url)
            let reopened = try await disk.read(url)
            let recovered = try KeepDataEnvelope.decode(reopened)
            guard bytes == reopened, recovered == payload else { throw ImportFailure.backupFailed }
            return url
        } catch { throw ImportFailure.backupFailed }
    }
    func candidateBytes(_ payload: KeepDataPayload, workspace: TimesheetLedger, settings: SettingsArchive) async throws -> [String: Data] {
        try payload.validate()
        let ledger = TimesheetLedger(tracked: payload.workspace, configuration: workspace)
        let preferences = payload.applyingContent(to: settings)
        guard preferences.isValid else { throw ImportFailure.invalidArchive }
        return [
            "keep.timesheet.v1": try await disk.encode(ledger),
            "keep.tasks.v1": try await disk.encode(payload.tasks),
            "keep.habits.v1": try await disk.encode(payload.habits),
            "keep.preferences.v1": try await disk.encode(preferences)
        ]
    }
}
