import Foundation
import CoreFoundation
import Observation

@Observable final class BackupRestoreGate {
    var isLocked = false
    var generation = UUID()
    var recoveryError: String?
}

protocol BackupFileStorage: Actor {
    nonisolated var root: URL { get }
    func encode<T: Encodable>(_ value: T) async throws -> Data
    func decode<T: Decodable>(_ type: T.Type, data: Data) async throws -> T
    func prepare(_ payload: BackupPayload, deviceID: UUID, date: Date, appVersion: String) async throws -> BackupEnvelope
    func validatedEnvelope(_ data: Data) async throws -> BackupEnvelope
    func payload(_ envelope: BackupEnvelope) async throws -> BackupPayload
    func exists(_ url: URL) async -> Bool
    func read(_ url: URL) async throws -> Data
    func write(_ data: Data, to url: URL) async throws
    func remove(_ url: URL) async throws
    func recoveryFiles() async throws -> [URL]
    func pruneRawRecovery(keeping count: Int) async throws
}

/// All filesystem work runs on this actor, never on the UI executor.
actor BackupLocalFiles: BackupFileStorage {
    nonisolated let root: URL
    init(root: URL) { self.root = root }
    static var applicationRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keep/Backups", isDirectory: true)
    }

    func prepare(_ payload: BackupPayload, deviceID: UUID, date: Date, appVersion: String) throws -> BackupEnvelope {
        try payload.validate()
        let bytes = try encode(payload)
        // Canonicalize Set-backed fields so relaunches do not create false dirty backups.
        guard var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw BackupFailure.invalidArchive }
        if var workspace = object["workspace"] as? [String: Any] {
            if let ids = workspace["deletedProjectIDs"] as? [String] { workspace["deletedProjectIDs"] = ids.sorted() }
            object["workspace"] = workspace
        }
        if var tasks = object["tasks"] as? [String: Any], let hidden = tasks["hiddenHabitIDs"] as? [String: [String]] {
            tasks["hiddenHabitIDs"] = hidden.mapValues { $0.sorted() }; object["tasks"] = tasks
        }
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard canonical.count <= BackupEnvelope.maximumBytes / 2 else { throw BackupFailure.tooLarge }
        return BackupEnvelope(payload: canonical, deviceID: deviceID, date: date, appVersion: appVersion)
    }
    func payload(_ envelope: BackupEnvelope) throws -> BackupPayload { try envelope.validatedPayload() }
    func validatedEnvelope(_ data: Data) throws -> BackupEnvelope { try BackupEnvelope.decode(data) }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func pruneRawRecovery(keeping count: Int) throws {
        let folder = root.appendingPathComponent("Recovery")
        let files = try newestFirst(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.hasSuffix(".raw-recovery.json") })
        for url in files.dropFirst(count) { try FileManager.default.removeItem(at: url) }
    }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
    func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, count <= BackupEnvelope.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return try Data(contentsOf: url)
    }
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize(); try handle.close()
        guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
    }
    func remove(_ url: URL) throws { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
    private func newestFirst(_ urls: [URL]) throws -> [URL] {
        var dated: [(url: URL, date: Date)] = []
        for url in urls {
            let date = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
            dated.append((url, date))
        }
        dated.sort { left, right in
            if left.date == right.date { return left.url.lastPathComponent > right.url.lastPathComponent }
            return left.date > right.date
        }
        return dated.map { $0.url }
    }
    func recoveryFiles() throws -> [URL] {
        let folder = root.appendingPathComponent("Recovery", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try newestFirst(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "keepbackup" })
    }
}

/// A raw local recovery also preserves unreadable archives. Raw bytes never enter iCloud.
nonisolated struct RestoreJournal: Codable {
    let original: [String: Data]
    let absentKeys: [String]
    let candidate: [String: Data]
    var committed = false
}

final class BackupRestoreTransaction {
    static let keys = ["keep.timesheet.v1", "keep.tasks.v1", "keep.habits.v1", "keep.preferences.v1"]
    let defaults: UserDefaults
    let domain: String
    let root: URL
    let disk: any BackupFileStorage
    var synchronize: () -> Bool
    // Failure injection operates only in isolated checks.
    var beforeWrite: ((Int) throws -> Void)?

    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "com.youssef.keep", root: URL = BackupLocalFiles.applicationRoot, disk: (any BackupFileStorage)? = nil) {
        self.defaults = defaults; self.domain = domain; self.root = disk?.root ?? root; self.disk = disk ?? BackupLocalFiles(root: root)
        synchronize = { CFPreferencesAppSynchronize(domain as CFString) }
    }
    var journalURL: URL { root.appendingPathComponent("restore-journal.json") }

    /// Must run before any stores are constructed. Incomplete restores roll back, committed ones stand.
    func recoverBeforeLoading() throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        let journal = try JSONDecoder().decode(RestoreJournal.self, from: Data(contentsOf: journalURL))
        guard Set(journal.original.keys).isSubset(of: Set(Self.keys)),
              Set(journal.candidate.keys) == Set(Self.keys),
              Set(journal.absentKeys).isSubset(of: Set(Self.keys)),
              Set(journal.original.keys).union(journal.absentKeys) == Set(Self.keys),
              Set(journal.original.keys).isDisjoint(with: journal.absentKeys) else { throw BackupFailure.invalidArchive }
        if !journal.committed { try replace(journal.original, absent: journal.absentKeys, inject: false) }
        try FileManager.default.removeItem(at: journalURL)
    }

    func originalJournal(candidate: [String: Data]) throws -> RestoreJournal {
        guard synchronize() else { throw BackupFailure.writeFailed }
        var original: [String: Data] = [:]; var absent: [String] = []
        for key in Self.keys {
            if let value = defaults.object(forKey: key) {
                // Preserve unexpected property-list types without overwriting them silently.
                guard let data = value as? Data else { throw BackupFailure.localDataUnavailable }
                original[key] = data
            } else { absent.append(key) }
        }
        return RestoreJournal(original: original, absentKeys: absent, candidate: candidate)
    }

    func apply(_ journal: RestoreJournal) async throws {
        try await disk.write(try await disk.encode(journal), to: journalURL)
        do {
            try replace(journal.candidate, absent: [], inject: true)
        } catch {
            // Leave the uncommitted journal in place if rollback itself fails.
            try replace(journal.original, absent: journal.absentKeys, inject: false)
            try await disk.remove(journalURL)
            throw error
        }
        // Candidate keys are durable. A marker-write error must never trigger rollback:
        // the committed marker may already exist. Startup chooses one complete snapshot.
        var completed = journal; completed.committed = true
        try await disk.write(try await disk.encode(completed), to: journalURL)
        try await disk.remove(journalURL)
    }

    private func replace(_ values: [String: Data], absent: [String], inject: Bool) throws {
        for (index, key) in Self.keys.enumerated() {
            if inject { try beforeWrite?(index) }
            if let value = values[key] { defaults.set(value, forKey: key) }
            else if absent.contains(key) { defaults.removeObject(forKey: key) }
        }
        // Explicit durability is required here, unlike ordinary preference saves.
        guard synchronize(), Self.keys.allSatisfy({ values[$0] == defaults.data(forKey: $0) }) else { throw BackupFailure.writeFailed }
    }
}
