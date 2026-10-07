import Foundation
import CryptoKit

/// Backups deliberately contain no live timer, playback, cache or security-scoped resource.
nonisolated struct PortableSettings: Codable {
    let appearance: AppAppearance
    let wallpaperSource: WallpaperSource
    let wallpaperOrder: WallpaperOrder
    let rotationSeconds: Int
    let automaticallyRotate: Bool
    let glassStyle: MusicGlassStyle
    let glassiness: Double
    let channels: [MusicChannel]
    let selectedChannelID: String?
    let musicProvider: MusicProvider?
    let musicVolume: Double?
    let menuBarEnabled: Bool?
    let menuBarTimer: MenuBarTimer?
    let menuBarShowSeconds: Bool?
    let weeklyFocusGoalMinutes: Int?
    let wallpaperRotationTrigger: WallpaperRotationTrigger?
    let customRotationMinutes: Int?

    init(_ s: SettingsArchive) {
        appearance = s.appearance; wallpaperSource = s.wallpaperSource; wallpaperOrder = s.wallpaperOrder
        rotationSeconds = s.rotationSeconds; automaticallyRotate = s.automaticallyRotate
        glassStyle = s.glassStyle; glassiness = s.glassiness; channels = s.channels
        selectedChannelID = s.selectedChannelID; musicProvider = s.musicProvider; musicVolume = s.musicVolume
        menuBarEnabled = s.menuBarEnabled; menuBarTimer = s.menuBarTimer; menuBarShowSeconds = s.menuBarShowSeconds
        weeklyFocusGoalMinutes = s.weeklyFocusGoalMinutes; wallpaperRotationTrigger = s.wallpaperRotationTrigger
        customRotationMinutes = s.customRotationMinutes
    }

    func applying(to local: SettingsArchive) -> SettingsArchive {
        var s = local
        s.appearance = appearance; s.wallpaperSource = wallpaperSource; s.wallpaperOrder = wallpaperOrder
        s.rotationSeconds = rotationSeconds; s.automaticallyRotate = automaticallyRotate
        s.glassStyle = glassStyle; s.glassiness = glassiness; s.channels = channels
        s.selectedChannelID = selectedChannelID; s.musicProvider = musicProvider; s.musicVolume = musicVolume
        s.menuBarEnabled = menuBarEnabled; s.menuBarTimer = menuBarTimer; s.menuBarShowSeconds = menuBarShowSeconds
        s.weeklyFocusGoalMinutes = weeklyFocusGoalMinutes; s.wallpaperRotationTrigger = wallpaperRotationTrigger
        s.customRotationMinutes = customRotationMinutes
        return s
    }
}

nonisolated struct BackupPayload: Codable {
    let workspace: TimesheetLedger
    let tasks: TaskArchive
    let habits: HabitArchive
    let settings: PortableSettings

    func validate() throws {
        try TimesheetPersistence.validate(workspace)
        try TaskPersistence.validate(tasks)
        guard habits.isValid, settings.applying(to: SettingsArchive()).isValid else { throw BackupFailure.invalidArchive }
    }

    var summary: String {
        "\(workspace.customProjects.filter { !workspace.deletedProjectIDs.contains($0.id) }.count + FocusProject.defaults.filter { !workspace.deletedProjectIDs.contains($0.id) }.count) projects · \(workspace.sessions.count) sessions · \(tasks.days.values.reduce(0) { $0 + $1.count }) tasks · \(habits.habits.count) habits"
    }
}

nonisolated struct BackupEnvelope: Codable, Identifiable {
    static let maximumBytes = 128 * 1024 * 1024
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let appVersion: String
    let deviceID: UUID
    let payload: Data
    let checksum: String

    init(snapshot: BackupPayload, deviceID: UUID, date: Date, appVersion: String) throws {
        try snapshot.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        payload = try encoder.encode(snapshot)
        guard payload.count <= Self.maximumBytes / 2 else { throw BackupFailure.tooLarge }
        checksum = Self.digest(payload)
        schemaVersion = 1; id = UUID(); createdAt = date; self.appVersion = appVersion; self.deviceID = deviceID
    }

    init(payload: Data, deviceID: UUID, date: Date, appVersion: String) {
        self.payload = payload; checksum = Self.digest(payload)
        schemaVersion = 1; id = UUID(); createdAt = date; self.appVersion = appVersion; self.deviceID = deviceID
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func validatedPayload() throws -> BackupPayload {
        guard schemaVersion == 1 else { throw BackupFailure.unsupportedVersion }
        guard createdAt.timeIntervalSince1970.isFinite, createdAt >= .distantPast, createdAt <= .distantFuture,
              !appVersion.isEmpty, appVersion.count <= 100, payload.count <= Self.maximumBytes / 2,
              checksum == Self.digest(payload) else { throw BackupFailure.invalidArchive }
        let decoded = try JSONDecoder().decode(BackupPayload.self, from: payload)
        try decoded.validate()
        return decoded
    }

    static func decode(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= maximumBytes else { throw BackupFailure.tooLarge }
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        _ = try envelope.validatedPayload()
        return envelope
    }

    static func date(fromFilename filename: String) -> Date? {
        guard filename.hasSuffix(".keepbackup") else { return nil }
        let parts = filename.dropLast(".keepbackup".count).split(separator: "_")
        guard parts.count == 2, UUID(uuidString: String(parts[1])) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
        for pattern in ["yyyyMMdd'T'HHmmss.SSS'Z'", "yyyyMMdd'T'HHmmss'Z'"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: String(parts[0])), formatter.string(from: date) == String(parts[0]) { return date }
        }
        return nil
    }

    var filename: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return "\(formatter.string(from: createdAt))_\(id.uuidString).keepbackup"
    }
}

nonisolated struct BackupVersion: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let deviceID: String
    var uploaded = false
    var uploading = false
    var downloaded = false
    var error: String?
    var isRecovery = false
    var id: String { url.path }
}

nonisolated enum BackupRetention {
    static func removals(_ versions: [BackupVersion], deviceID: UUID, now: Date) -> [BackupVersion] {
        let own = versions.filter { $0.deviceID == deviceID.uuidString && $0.uploaded && !$0.isRecovery }
            .sorted { $0.createdAt > $1.createdAt }
        var keep = Set(own.prefix(24).map(\.id))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        var days = Set<Date>()
        for version in own where version.createdAt >= cutoff {
            if days.insert(calendar.startOfDay(for: version.createdAt)).inserted { keep.insert(version.id) }
        }
        return own.filter { !keep.contains($0.id) }
    }
}

nonisolated enum BackupFailure: LocalizedError {
    case invalidArchive, unsupportedVersion, tooLarge, localDataUnavailable, restoreLocked, unavailable, accountChanged, writeFailed
    var errorDescription: String? {
        switch self {
        case .invalidArchive: "This backup is damaged or contains invalid data. Choose another version."
        case .unsupportedVersion: "This backup needs a different version of Keep. Update Keep and try again."
        case .tooLarge: "This backup is too large to open safely. Choose another version."
        case .localDataUnavailable: "Saved data couldn’t be read or saved. Resolve the local storage error before backing up."
        case .restoreLocked: "Restore recovery must finish before Keep can change saved data."
        case .unavailable: "iCloud Drive is unavailable. Sign in and enable iCloud Drive in System Settings, then retry."
        case .accountChanged: "Your iCloud account changed. Enable backup again to use this account."
        case .writeFailed: "Keep couldn’t verify the saved data. Check available disk space and retry."
        }
    }
}
