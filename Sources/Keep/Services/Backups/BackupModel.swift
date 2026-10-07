import Foundation
import Observation

struct BackupLocalState: Codable {
    var automatic = false
    var deviceID = UUID()
    var account: Data?
    var lastCreated: Date?
    var lastChecksum: String?
    var lastUploadConfirmed: Date?
    var queuedIsAutomatic: Bool?
    var activeURL: URL?
    var isValid: Bool {
        [lastCreated, lastUploadConfirmed].compactMap { $0 }.allSatisfy {
            $0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture
        } && (account?.count ?? 0) <= 1_048_576
        && (activeURL == nil || (activeURL?.isFileURL == true && activeURL?.pathExtension == "keepbackup"))
    }
}

@Observable final class BackupModel {
    enum Status: Equatable {
        case disabled, ready, preparing, pending, uploading, uploaded, offline, unavailable, restoring, error(String)
        var message: String {
            switch self {
            case .disabled: "Automatic backup is off."
            case .ready: "Ready to back up."
            case .preparing: "Preparing backup…"
            case .pending: "Backup saved on this Mac. Pending upload."
            case .uploading: "Uploading backup…"
            case .uploaded: "Upload confirmed by iCloud."
            case .offline: "Offline. Backup will upload when iCloud is available."
            case .unavailable: "iCloud Drive is unavailable. Check your iCloud settings, then retry."
            case .restoring: "Restoring your backup…"
            case .error(let text): text
            }
        }
    }
    private(set) var status: Status = .disabled
    private(set) var versions: [BackupVersion] = []
    private(set) var preview: BackupEnvelope?
    private(set) var previewSummary = ""
    private(set) var restoreActivity: String?
    private(set) var recoveryWarning: String?
    private(set) var busy = false
    private(set) var localState: BackupLocalState
    private(set) var configurationError: String?
    let gate: BackupRestoreGate
    var automatic: Bool { localState.automatic }
    var canRetryUpload: Bool { configurationError == nil && cloud.account != nil && cloud.accountMatches(localState.account) && (active != nil || queued != nil) }
    var lastUploadConfirmed: Date? { localState.lastUploadConfirmed }
    @ObservationIgnored let cloud: any BackupCloudStorage
    @ObservationIgnored let disk: any BackupFileStorage
    @ObservationIgnored let transaction: BackupRestoreTransaction
    @ObservationIgnored private let workspace: WorkspaceModel
    @ObservationIgnored private let tasks: DailyTaskStore
    @ObservationIgnored private let habits: HabitStore
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let music: MusicPlayerModel
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var active: BackupEnvelope?
    @ObservationIgnored private var queued: BackupEnvelope?
    @ObservationIgnored private var previewPayload: BackupPayload?
    @ObservationIgnored private var previewRequest = UUID()
    @ObservationIgnored private var previewEpoch: UUID?
    @ObservationIgnored private var handling = false
    private static let stateKey = "keep.backup.local.v1"

    init(workspace: WorkspaceModel, tasks: DailyTaskStore, habits: HabitStore, preferences: AppPreferences,
         music: MusicPlayerModel, gate: BackupRestoreGate, cloud: (any BackupCloudStorage)? = nil,
         transaction: BackupRestoreTransaction = BackupRestoreTransaction(), defaults: UserDefaults = .standard,
         now: @escaping () -> Date = { .now }) {
        self.workspace = workspace; self.tasks = tasks; self.habits = habits; self.preferences = preferences
        self.music = music; self.gate = gate; self.cloud = cloud ?? ICloudBackupStorage(); self.transaction = transaction
        self.defaults = defaults; self.now = now; disk = transaction.disk
        if let value = defaults.object(forKey: Self.stateKey) {
            do {
                guard let data = value as? Data else { throw BackupFailure.invalidArchive }
                localState = try JSONDecoder().decode(BackupLocalState.self, from: data)
                guard localState.isValid else { throw BackupFailure.invalidArchive }
            } catch {
                localState = BackupLocalState()
                configurationError = "Backup settings couldn’t be opened. Saved bytes are preserved; automatic backup is disabled."
            }
        } else { localState = BackupLocalState() }
        self.cloud.onChange = { [weak self] in
            guard let self else { return }
            self.accountChangedIfNeeded()
            Task { guard !self.busy else { return }; await self.cloudChanged() }
        }
        if let error = gate.recoveryError { status = .error(error) }
        else { status = automatic ? .ready : .disabled }
    }
    private var activeFile: URL { disk.root.appendingPathComponent("Outbox/active.keepbackup") }
    private var queuedFile: URL { disk.root.appendingPathComponent("Outbox/queued.keepbackup") }

    func start() {
        guard loop == nil, !busy else { return }
        busy = true
        loop = Task { [weak self] in
            guard let self else { return }
            await self.loadOutbox()
            while !Task.isCancelled {
                await self.tick()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil }
    private func saveState() throws {
        guard configurationError == nil else { throw BackupFailure.localDataUnavailable }
        defaults.set(try JSONEncoder().encode(localState), forKey: Self.stateKey)
    }
    private func loadOutbox() async {
        defer { busy = false }
        for (url, isActive) in [(activeFile, true), (queuedFile, false)] {
            do {
                let exists = await disk.exists(url)
                guard exists else { continue }
                let data = try await disk.read(url)
                let value = try await disk.validatedEnvelope(data)
                guard value.deviceID == localState.deviceID else { throw BackupFailure.invalidArchive }
                if isActive { active = value } else { queued = value }
            } catch {
                configurationError = "A pending backup couldn’t be opened. Its file is preserved; new backups are paused. " + error.localizedDescription
                status = .error(configurationError ?? error.localizedDescription)
            }
        }
    }

    func setAutomatic(_ enabled: Bool) async {
        guard !busy, configurationError == nil, !gate.isLocked else { return }
        busy = true
        do {
            if enabled {
                guard let account = cloud.account else { busy = false; status = .unavailable; return }
                if !cloud.accountMatches(localState.account) { try await abandonOutbox() }
                guard cloud.accountMatches(account) else { throw BackupFailure.accountChanged }
                localState.account = account
            }
            if !enabled, localState.queuedIsAutomatic == true {
                try await disk.remove(queuedFile)
                queued = nil; localState.queuedIsAutomatic = nil
            }
            localState.automatic = enabled
            try saveState()
            status = enabled ? .ready : .disabled
        } catch { busy = false; status = .error(error.localizedDescription); return }
        busy = false
        if enabled { await backUpNow() }
    }
    private func accountChangedIfNeeded() {
        guard let previous = localState.account, !cloud.accountMatches(previous) else { return }
        epoch = UUID(); preview = nil; previewPayload = nil; previewEpoch = nil; localState.automatic = false; localState.account = nil; localState.activeURL = nil
        localState.lastUploadConfirmed = nil; localState.lastCreated = nil; localState.lastChecksum = nil
        // Do not copy queued data to a newly signed-in account.
        status = .error(BackupFailure.accountChanged.localizedDescription)
        do { try saveState() } catch { configurationError = error.localizedDescription }
    }
    private func abandonOutbox() async throws {
        try await disk.remove(activeFile); try await disk.remove(queuedFile)
        active = nil; queued = nil; localState.activeURL = nil; localState.queuedIsAutomatic = nil
    }
    func tick() async {
        accountChangedIfNeeded()
        guard !busy, !gate.isLocked, configurationError == nil, cloud.accountMatches(localState.account) else { return }
        if active != nil || queued != nil { await retryPending() }
        guard automatic, !busy else { return }
        if localState.lastCreated.map({ now().timeIntervalSince($0) < 3600 }) == true { return }
        busy = true; defer { busy = false }
        await createBackup(force: false)
    }
    func backUpNow() async {
        guard !busy, !gate.isLocked, configurationError == nil else { return }
        guard let account = cloud.account else { status = .unavailable; return }
        busy = true; defer { busy = false }
        do {
            if !cloud.accountMatches(localState.account) {
                epoch = UUID(); try await abandonOutbox()
                guard cloud.accountMatches(account) else { throw BackupFailure.accountChanged }
                localState.account = account; localState.lastChecksum = nil; localState.lastCreated = nil; localState.lastUploadConfirmed = nil
            }
            await createBackup(force: true)
        } catch { status = .error(error.localizedDescription) }
    }
    private func capture() throws -> BackupPayload {
        guard !tasks.loadFailed, !habits.loadFailed, preferences.canEdit,
              tasks.persistenceError == nil, habits.persistenceError == nil, preferences.persistenceError == nil else { throw BackupFailure.localDataUnavailable }
        let ledger = try workspace.captureBackup()
        // No suspension here: all four value archives represent this same main-actor checkpoint.
        return BackupPayload(workspace: ledger, tasks: tasks.archive, habits: habits.archive, settings: PortableSettings(preferences.snapshot))
    }
    private func createBackup(force: Bool) async {
        status = .preparing
        let token = epoch
        do {
            let payload = try capture()
            let envelope = try await disk.prepare(payload, deviceID: localState.deviceID, date: now(), appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            guard token == epoch, cloud.accountMatches(localState.account) else { throw BackupFailure.accountChanged }
            if !force, envelope.checksum == localState.lastChecksum {
                localState.lastCreated = now(); try saveState(); status = active == nil ? .ready : .pending; return
            }
            let encoded = try await disk.encode(envelope)
            _ = try await disk.validatedEnvelope(encoded)
            guard token == epoch else { throw BackupFailure.accountChanged }
            try await disk.write(encoded, to: queuedFile)
            queued = envelope; localState.queuedIsAutomatic = !force; localState.lastChecksum = envelope.checksum; localState.lastCreated = now()
            try saveState()
            await submitNext(token: token)
        } catch { status = .error(error.localizedDescription) }
    }
    func retryPending() async {
        guard !busy, !gate.isLocked, configurationError == nil else { return }
        accountChangedIfNeeded()
        guard cloud.account != nil, cloud.accountMatches(localState.account) else { return }
        busy = true; defer { busy = false }
        await submitNext(token: epoch)
    }
    private func submitNext(token: UUID) async {
        do {
            try await cloud.connect()
            guard token == epoch else { return }
            if active == nil, let next = queued {
                let data = try await disk.encode(next)
                try await disk.write(data, to: activeFile)
                active = next; queued = nil; localState.queuedIsAutomatic = nil
                try await disk.remove(queuedFile)
            }
            if let active, localState.activeURL == nil {
                let data = try await disk.encode(active)
                let url = try await cloud.submit(data, envelope: active)
                guard token == epoch else { return }
                localState.activeURL = url; try saveState()
                status = cloud.isOffline ? .offline : .pending
            }
            if active != nil { status = cloud.isOffline ? .offline : .pending }
            await cloudChanged()
        } catch { status = cloud.isOffline ? .offline : .error(error.localizedDescription) }
    }
    private func cloudChanged() async {
        guard !handling, !gate.isLocked else { return }
        handling = true
        let previousBusy = busy; busy = true
        defer { handling = false; busy = previousBusy }
        let token = epoch
        do {
            versions = cloud.versions + versions.filter(\.isRecovery)
            guard token == epoch, cloud.account != nil, cloud.accountMatches(localState.account) else { return }
            if let url = localState.activeURL, let item = cloud.versions.first(where: { $0.url == url }) {
                if let error = item.error { status = .error(error); return }
                if item.uploaded {
                    localState.lastUploadConfirmed = now(); localState.activeURL = nil
                    try saveState(); try await disk.remove(activeFile); active = nil
                    status = .uploaded
                    for version in BackupRetention.removals(cloud.versions, deviceID: localState.deviceID, now: now()) {
                        guard token == epoch else { return }
                        try await cloud.remove(version)
                    }
                } else { status = cloud.isOffline ? .offline : item.uploading ? .uploading : .pending }
            }
        } catch { status = .error(error.localizedDescription) }
    }
    private func recoveryVersions() async throws -> [BackupVersion] {
        var result: [BackupVersion] = []
        for url in try await disk.recoveryFiles() {
            do {
                let value = try await disk.validatedEnvelope(disk.read(url))
                result.append(BackupVersion(url: url, createdAt: value.createdAt, deviceID: value.deviceID.uuidString, downloaded: true, isRecovery: true))
            } catch { recoveryWarning = "Some local recovery copies could not be validated. Their files have been preserved." }
        }
        return result
    }
    func refreshVersions() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            versions = try await recoveryVersions()
            try await cloud.connect()
            await cloudChanged()
        } catch { status = .error(error.localizedDescription) }
    }
    func prepareRestore(_ version: BackupVersion) async {
        guard !busy, !gate.isLocked else { return }
        busy = true; preview = nil; previewPayload = nil
        restoreActivity = version.downloaded ? "Opening and validating backup…" : "Downloading and validating backup…"
        defer { busy = false; restoreActivity = nil }
        let token = epoch, request = UUID(); previewRequest = request
        do {
            let data = try await (version.isRecovery ? disk.read(version.url) : cloud.read(version))
            try Task.checkCancellation()
            guard data.count <= BackupEnvelope.maximumBytes else { throw BackupFailure.tooLarge }
            let value = try await disk.validatedEnvelope(data)
            guard token == epoch else { throw BackupFailure.accountChanged }
            let payload = try await disk.payload(value)
            try Task.checkCancellation()
            guard token == epoch, request == previewRequest else { throw BackupFailure.accountChanged }
            preview = value; previewPayload = payload; previewEpoch = token; previewSummary = payload.summary
        } catch is CancellationError { return }
        catch { if request == previewRequest { status = .error(error.localizedDescription) } }
    }
    func cancelPreview() { previewRequest = UUID(); preview = nil; previewPayload = nil; previewEpoch = nil }

    func restore() async {
        guard preview != nil, let candidate = previewPayload, previewEpoch == epoch, !busy, !gate.isLocked else { return }
        busy = true; status = .restoring
        defer { busy = false }
        do {
            workspace.stopBothTimers()
            let recovery: BackupPayload?
            if workspace.canTrack && tasks.canEdit && habits.canEdit && preferences.canEdit { recovery = try capture() }
            else { recovery = nil }
            let release = music.shutdown()
            gate.isLocked = true
            await release?.value
            var restoredWorkspace = candidate.workspace
            // Match normal legacy loading: start coverage now, without inventing completions.
            if restoredWorkspace.pomodoroHistoryStartedAt == nil { restoredWorkspace.beginPomodoroHistory(at: now()) }
            let settings = candidate.settings.applying(to: preferences.snapshot)
            guard settings.isValid else { throw BackupFailure.invalidArchive }
            let candidateBytes = [
                "keep.timesheet.v1": try await disk.encode(restoredWorkspace),
                "keep.tasks.v1": try await disk.encode(candidate.tasks),
                "keep.habits.v1": try await disk.encode(candidate.habits),
                "keep.preferences.v1": try await disk.encode(settings)
            ]
            let journal = try transaction.originalJournal(candidate: candidateBytes)
            let stamp = BackupEnvelope(payload: Data(), deviceID: localState.deviceID, date: now(), appVersion: "1.0").filename
            let rawURL = disk.root.appendingPathComponent("Recovery/\(stamp).raw-recovery.json")
            try await disk.write(try await disk.encode(journal), to: rawURL)
            if let recovery {
                let envelope = try await disk.prepare(recovery, deviceID: localState.deviceID, date: now(), appVersion: "1.0")
                try await disk.write(try await disk.encode(envelope), to: disk.root.appendingPathComponent("Recovery/\(envelope.filename)"))
            }
            try await transaction.apply(journal)
            workspace.installBackup(restoredWorkspace); habits.installBackup(candidate.habits)
            tasks.installBackup(candidate.tasks); preferences.installBackup(settings)
            gate.generation = UUID(); gate.isLocked = false; gate.recoveryError = nil
            music.selectChannel(preferences.selectedChannel)
            music.volume = preferences.musicVolume
            self.preview = nil; previewPayload = nil; previewEpoch = nil; localState.lastChecksum = nil; localState.lastCreated = nil
            queued = nil; localState.queuedIsAutomatic = nil; try await disk.remove(queuedFile)
            if configurationError == nil { try saveState() }
            status = .ready
            try await pruneRecovery()
            versions = cloud.versions + (try await recoveryVersions())
        } catch {
            if await disk.exists(transaction.journalURL) {
                gate.recoveryError = "Restore recovery is required. Restart Keep to recover safely. \(error.localizedDescription)"
                gate.isLocked = true
            } else { gate.isLocked = false }
            status = .error(error.localizedDescription)
        }
    }
    private func pruneRecovery() async throws {
        let files = try await disk.recoveryFiles()
        for url in files.dropFirst(3) { try await disk.remove(url) }
        // Raw recovery copies use their own bounded list and are never uploaded.
        try await disk.pruneRawRecovery(keeping: 3)
    }
}
