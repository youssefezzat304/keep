import AppKit
import Foundation

private final class SilentPlayback: MusicPlayback {
    var volume: Float = 0
    var stops = 0
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {}
    func play() {}
    func pause() {}
    func stop() { stops += 1 }
}
private struct SilentCatalog: MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack] { throw MusicFailure.noTracks }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { throw MusicFailure.noTracks }
    func streamURL(for track: MusicTrack) async throws -> URL { throw MusicFailure.unavailable }
}
private actor SilentAppleMusic: AppleMusicControlling {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot { .init(state: .stopped, title: nil, artist: nil) }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage { .init(items: [], hasMore: false) }
}
private final class FakeCloud: BackupCloudStorage {
    var account: Data? = Data("account-a".utf8)
    var versions: [BackupVersion] = []
    var isOffline = false
    var onChange: (() -> Void)?
    var submissions: [UUID: Data] = [:]
    var submissionCalls = 0
    var removed: [BackupVersion] = []
    var failWrites = false
    var connectFailure = false
    var holdRead = false
    var readContinuation: CheckedContinuation<Void, Never>?
    var holdSubmission = false
    var continuation: CheckedContinuation<Void, Never>?
    func connect() async throws { if connectFailure || account == nil { throw BackupFailure.unavailable } }
    func submit(_ data: Data, envelope: BackupEnvelope) async throws -> URL {
        submissionCalls += 1
        let expected = account
        if holdSubmission { await withCheckedContinuation { continuation = $0 } }
        guard account == expected else { throw BackupFailure.accountChanged }
        if failWrites { throw BackupFailure.writeFailed }
        submissions[envelope.id] = data
        let url = URL(fileURLWithPath: "/fake-cloud/\(envelope.deviceID.uuidString)/\(envelope.filename)")
        if !versions.contains(where: { $0.url == url }) {
            versions.append(BackupVersion(url: url, createdAt: envelope.createdAt, deviceID: envelope.deviceID.uuidString, downloaded: true))
        }
        return url
    }
    func read(_ version: BackupVersion) async throws -> Data {
        if holdRead { await withCheckedContinuation { readContinuation = $0 } }
        try Task.checkCancellation()
        for data in submissions.values {
            if try BackupEnvelope.decode(data).filename == version.url.lastPathComponent { return data }
        }
        throw BackupFailure.invalidArchive
    }
    func remove(_ version: BackupVersion) async throws { removed.append(version); versions.removeAll { $0.id == version.id } }
    func confirm() { for i in versions.indices { versions[i].uploaded = true }; onChange?() }
}
private final class TestClock { var date = Date(timeIntervalSince1970: 1_791_374_400) }
private final class Fixture {
    let suite = "keep.backup.checks.\(UUID().uuidString)"
    let defaults: UserDefaults
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("keep-backup-checks-\(UUID().uuidString)")
    let gate = BackupRestoreGate()
    let cloud = FakeCloud()
    let clock = TestClock()
    let playback = SilentPlayback()
    let transaction: BackupRestoreTransaction
    let workspace: WorkspaceModel
    let tasks: DailyTaskStore
    let habits: HabitStore
    let preferences: AppPreferences
    let music: MusicPlayerModel
    let backup: BackupModel
    init() throws {
        guard let defaults = UserDefaults(suiteName: suite) else { throw BackupFailure.writeFailed }; self.defaults = defaults
        transaction = BackupRestoreTransaction(defaults: defaults, domain: suite, root: root)
        var wp = TimesheetPersistence(defaults: defaults); wp.access = gate
        var tp = TaskPersistence(defaults: defaults); tp.access = gate
        var hp = HabitPersistence(defaults: defaults); hp.access = gate
        var sp = SettingsPersistence(defaults: defaults); sp.access = gate
        workspace = WorkspaceModel(persistence: wp)
        habits = HabitStore(persistence: hp); tasks = DailyTaskStore(persistence: tp, habits: habits)
        preferences = AppPreferences(persistence: sp)
        music = MusicPlayerModel(catalog: SilentCatalog(), playback: playback, preferences: preferences, appleMusic: SilentAppleMusic(), launchAppleMusic: {}, isMusicRunning: { false })
        backup = BackupModel(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, music: music,
                             gate: gate, cloud: cloud, transaction: transaction, defaults: defaults, now: { [clock] in clock.date })
    }
    func clean() async throws {
        backup.stop(); workspace.shutdown(); await music.shutdown()?.value
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
}

@main enum BackupChecks {
    static var count = 0
    static func expect(_ value: Bool, _ message: String) { count += 1; precondition(value, message) }
    static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure(message) } catch { count += 1 }
    }
    static func drain() async throws { try await Task.sleep(for: .milliseconds(100)) }
    static func main() async throws {
        _ = NSApplication.shared
        let f = try Fixture()
        expect(!f.backup.automatic && f.backup.lastUploadConfirmed == nil, "Opt in only; no invented success")
        let day = TaskDay.id(for: .now, calendar: f.tasks.calendar)
        let project = try f.workspace.createProject(name: "Backup project", accent: .sage)
        f.workspace.selectProject(project); f.workspace.setTaskName("Saved suggestion")
        f.workspace.play(.flow); try await Task.sleep(for: .milliseconds(15)); f.workspace.stop(.flow)
        f.workspace.edit(seconds: 1234, project: project, dayID: day)
        _ = f.tasks.add("Original task", on: day)
        let habit = try f.habits.add(name: "Read", icon: .book, startDay: day, endDay: nil, goal: .checkIn)
        _ = f.habits.setAmount(1, habitID: habit.id, on: day)
        f.tasks.remove(taskID: habit.id, on: day, habitID: habit.id)
        f.preferences.setFolder(bookmark: Data("local-folder-only".utf8), name: "Device folder")
        f.preferences.appearance = .dark; f.preferences.menuBarShowSeconds = false
        await f.backup.backUpNow()
        expect(f.cloud.submissions.count == 1, "One immutable cloud submission")
        expect(f.backup.lastUploadConfirmed == nil && f.backup.status == .pending, "Local creation is not upload success")
        guard let originalBytes = f.cloud.submissions.values.first else { throw BackupFailure.invalidArchive }
        let original = try BackupEnvelope.decode(originalBytes); let payload = try original.validatedPayload()
        expect(payload.workspace.customProjects.contains { $0.id == project.id }, "Project catalog included")
        expect(payload.workspace.sessions.count == 1 && payload.workspace.taskActivities.count == 1, "Sessions and suggestions included")
        expect(payload.workspace.entries.first { $0.project.id == project.id && $0.dayID == day }?.seconds == 1234, "Adjusted totals stay independent")
        expect(payload.tasks.days[day]?.count == 1 && payload.tasks.hiddenHabitIDs[day]?.contains(habit.id) == true, "Tasks and hidden projections included")
        expect(payload.habits.logs.count == 1 && payload.settings.appearance == .dark, "Habits and settings included")
        let text = String(decoding: original.payload, as: UTF8.self)
        expect(!text.contains("folderBookmark") && !text.contains("Device folder") && !text.contains("local-folder-only") && !text.contains("automaticBackup"), "Device access and local backup state excluded")
        f.cloud.confirm(); try await drain()
        expect(f.backup.lastUploadConfirmed == f.clock.date, "Metadata confirms success")
        await f.backup.setAutomatic(true)
        expect(f.backup.automatic, "Automatic enable is explicit")
        f.cloud.confirm(); try await drain()
        let initialCount = f.cloud.submissions.count
        _ = f.tasks.add("New task", on: day)
        f.clock.date += 3599; await f.backup.tick()
        expect(f.cloud.submissions.count == initialCount, "Hourly limit applies to actual changes")
        f.clock.date += 1; await f.backup.tick()
        expect(f.cloud.submissions.count == initialCount + 1, "Changed data after one hour backs up")
        f.cloud.confirm(); try await drain()
        f.clock.date += 3600; await f.backup.tick()
        expect(f.cloud.submissions.count == initialCount + 1, "Unchanged data does not create another version")
        await f.backup.backUpNow()
        expect(f.cloud.submissions.count == initialCount + 2, "Manual backup bypasses cadence")
        await f.backup.backUpNow(); await f.backup.backUpNow()
        expect(f.cloud.submissions.count == initialCount + 2, "Pending submissions remain bounded")
        let queuedPath = f.root.appendingPathComponent("Outbox/queued.keepbackup")
        expect(FileManager.default.fileExists(atPath: queuedPath.path), "Latest queued snapshot is durable")
        f.cloud.isOffline = true; await f.backup.retryPending()
        expect(f.backup.status == .offline && f.backup.lastUploadConfirmed != nil, "Offline status retains previous success")
        f.cloud.isOffline = false; f.cloud.confirm(); try await drain()

        // A whole restore resets runtime, restores all stores and preserves device access.
        let originalVersion = BackupVersion(url: URL(fileURLWithPath: "/fake-cloud/\(original.deviceID.uuidString)/\(original.filename)"), createdAt: original.createdAt, deviceID: original.deviceID.uuidString, uploaded: true, downloaded: true)
        await f.backup.prepareRestore(originalVersion)
        expect(f.backup.preview?.id == original.id && !f.backup.previewSummary.isEmpty, "Validated preview before mutation")
        _ = f.tasks.add("Replace me", on: day); f.workspace.startBothTimers()
        let priorGeneration = f.gate.generation
        await f.backup.restore()
        expect(f.backup.preview == nil && !f.gate.isLocked, "Successful restore releases gate")
        expect(f.tasks.archive.days[day]?.map(\.title) == ["Original task"], "Task snapshot replaces, never merges")
        expect(f.habits.archive.logs == payload.habits.logs, "Habit snapshot restored")
        expect(f.workspace.pomodoro.phase() == .idle && f.workspace.flow.phase() == .idle, "Both timers reset to idle")
        expect(f.workspace.selectedProject == nil && f.workspace.taskName.isEmpty && f.workspace.lastTimesheetRemoval == nil, "Runtime target and Undo cleared")
        expect(f.gate.generation != priorGeneration, "All windows invalidate stale drafts")
        expect(f.preferences.snapshot.folderBookmark == Data("local-folder-only".utf8), "Local folder permissions retained")
        expect(!f.music.wantsPlayback && f.playback.stops > 0, "Restore never autoplays")
        expect(f.backup.versions.contains { $0.isRecovery }, "Recovery versions exposed")
        expect(!FileManager.default.fileExists(atPath: f.transaction.journalURL.path), "Completed journal cleaned")
        let reloaded = try TimesheetPersistence(defaults: f.defaults).load()
        expect(reloaded.sessions.count == payload.workspace.sessions.count, "Restore adds no duplicate recording segments")
        expect(try TaskPersistence(defaults: f.defaults).load() == payload.tasks, "Restored data persists")

        // Gate protects every owner, not only the visible window.
        f.gate.isLocked = true
        let savedTasks = f.tasks.archive
        expect(!f.tasks.add("Blocked", on: day), "Task writes gated")
        f.workspace.play(.flow); f.workspace.selectProject(project); f.preferences.appearance = .light
        expect(!f.workspace.canTrack && !f.habits.canEdit && !f.preferences.canEdit && f.tasks.archive == savedTasks, "All shared owners gated")
        expect(f.workspace.flow.phase() == .idle && f.preferences.appearance == .dark, "Commands cannot bypass restore gate")
        f.gate.isLocked = false

        // Injection after two writes must roll back all four persisted keys and preserve live models.
        await f.backup.prepareRestore(originalVersion)
        _ = f.tasks.add("Keep after failed restore", on: day)
        let before = try TaskPersistence(defaults: f.defaults).load()
        f.transaction.beforeWrite = { if $0 == 2 { throw BackupFailure.writeFailed } }
        await f.backup.restore()
        expect(try TaskPersistence(defaults: f.defaults).load() == before && f.tasks.archive == before, "Partial restore rolls back persisted and live data")
        expect(!f.gate.isLocked && f.backup.preview != nil, "Safe rollback permits retry")
        f.transaction.beforeWrite = nil

        // Restart recovery runs before any stores. Missing keys are restored as missing.
        var candidate: [String: Data] = [:]
        for key in BackupRestoreTransaction.keys { candidate[key] = Data("candidate".utf8) }
        f.defaults.removeObject(forKey: "keep.preferences.v1")
        let journal = try f.transaction.originalJournal(candidate: candidate)
        try await f.transaction.disk.write(try await f.transaction.disk.encode(journal), to: f.transaction.journalURL)
        f.defaults.set(candidate["keep.timesheet.v1"], forKey: "keep.timesheet.v1")
        f.defaults.set(candidate["keep.preferences.v1"], forKey: "keep.preferences.v1")
        try f.transaction.recoverBeforeLoading()
        expect(f.defaults.data(forKey: "keep.timesheet.v1") == journal.original["keep.timesheet.v1"], "Restart rolls back interrupted workspace replacement")
        expect(f.defaults.object(forKey: "keep.preferences.v1") == nil, "Restart restores absent keys")
        var committed = journal; committed.committed = true
        try await f.transaction.disk.write(try await f.transaction.disk.encode(committed), to: f.transaction.journalURL)
        f.defaults.set(candidate["keep.tasks.v1"], forKey: "keep.tasks.v1")
        try f.transaction.recoverBeforeLoading()
        expect(f.defaults.data(forKey: "keep.tasks.v1") == candidate["keep.tasks.v1"], "Committed journal never rolls back later edits")

        // Invalid cloud files never change stores or yield preview.
        var object = try JSONSerialization.jsonObject(with: originalBytes) as? [String: Any] ?? [:]
        object["schemaVersion"] = 99
        rejects("Reject unknown schemas") { _ = try BackupEnvelope.decode(JSONSerialization.data(withJSONObject: object)) }
        object["schemaVersion"] = 1; object["checksum"] = "bad"
        rejects("Reject altered payload") { _ = try BackupEnvelope.decode(JSONSerialization.data(withJSONObject: object)) }
        rejects("Reject malformed archive") { _ = try BackupEnvelope.decode(Data("broken".utf8)) }
        rejects("Reject oversized archive before decoding") { _ = try BackupEnvelope.decode(Data(count: BackupEnvelope.maximumBytes + 1)) }
        var badSettings = SettingsArchive(); badSettings.glassiness = .nan
        rejects("Validate every store") { try BackupPayload(workspace: TimesheetLedger(), tasks: TaskArchive(), habits: HabitArchive(), settings: PortableSettings(badSettings)).validate() }
        let legacy = try JSONDecoder().decode(TimesheetLedger.self, from: Data("{\"entries\":[]}".utf8))
        try TimesheetPersistence.validate(legacy)
        expect(legacy.sessions.isEmpty && legacy.completedPomodoros.isEmpty && legacy.taskActivities.isEmpty, "Legacy ledger defaults survive backup validation")

        // Different accounts cannot inherit opt-in, upload status or pending snapshots.
        f.cloud.account = Data("account-b".utf8); f.cloud.onChange?(); try await drain()
        expect(!f.backup.automatic && f.backup.lastUploadConfirmed == nil, "Account change revokes automatic consent and account-specific success")
        let calls = f.cloud.submissionCalls; await f.backup.retryPending()
        expect(f.cloud.submissionCalls == calls, "Old outbox never uploads to a different account")
        try await f.clean()

        let broken = try Fixture()
        broken.defaults.set(Data("corrupt".utf8), forKey: "keep.tasks.v1")
        let protectedTasks = DailyTaskStore(persistence: TaskPersistence(defaults: broken.defaults))
        let blocked = BackupModel(workspace: broken.workspace, tasks: protectedTasks, habits: broken.habits, preferences: broken.preferences, music: broken.music, gate: broken.gate, cloud: broken.cloud, transaction: broken.transaction, defaults: broken.defaults)
        await blocked.backUpNow()
        expect(broken.cloud.submissions.isEmpty && protectedTasks.loadFailed, "Unreadable local stores cannot become empty backups")
        expect(broken.defaults.data(forKey: "keep.tasks.v1") == Data("corrupt".utf8), "Failed backup preserves corrupt bytes")
        try await broken.clean()

        let resumed = try Fixture()
        await resumed.backup.backUpNow()
        let newModel = BackupModel(workspace: resumed.workspace, tasks: resumed.tasks, habits: resumed.habits, preferences: resumed.preferences, music: resumed.music, gate: resumed.gate, cloud: resumed.cloud, transaction: resumed.transaction, defaults: resumed.defaults, now: { [clock = resumed.clock] in clock.date })
        newModel.start(); try await drain()
        expect(resumed.cloud.submissions.count == 1, "Relaunch retries the same immutable file without duplicate versions")
        resumed.cloud.confirm(); try await drain()
        expect(newModel.lastUploadConfirmed != nil, "Upload confirmation works after relaunch with automatic backup off")
        newModel.stop(); try await resumed.clean()

        let changed = try Fixture()
        changed.cloud.holdSubmission = true
        let request = Task { await changed.backup.backUpNow() }
        for _ in 0..<100 {
            if changed.cloud.continuation != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        changed.cloud.account = Data("different".utf8); changed.cloud.onChange?()
        changed.cloud.continuation?.resume(); await request.value
        expect(changed.cloud.submissions.isEmpty && changed.backup.lastUploadConfirmed == nil, "Account fencing rejects an in-flight write")
        changed.cloud.account = nil; changed.cloud.onChange?(); try await drain()
        expect(changed.backup.lastUploadConfirmed == nil, "Sign-out cannot confirm stale metadata")
        try await changed.clean()

        let canonical = try Fixture()
        var hidden = TaskArchive(); hidden.hiddenHabitIDs[day] = Set((0..<30).map { _ in UUID() })
        let value = BackupPayload(workspace: TimesheetLedger(), tasks: hidden, habits: HabitArchive(), settings: PortableSettings(SettingsArchive()))
        let one = try await canonical.transaction.disk.prepare(value, deviceID: UUID(), date: .now, appVersion: "1")
        let roundTrip = try JSONDecoder().decode(BackupPayload.self, from: JSONEncoder().encode(value))
        let two = try await canonical.transaction.disk.prepare(roundTrip, deviceID: UUID(), date: .now, appVersion: "1")
        expect(one.checksum == two.checksum, "Set-backed fields have stable dirty fingerprints after decode")
        expect(BackupEnvelope.date(fromFilename: one.filename) != nil && BackupEnvelope.date(fromFilename: "malformed.keepbackup") == nil, "Version filenames use strict UTC dates and UUIDs")
        try await canonical.clean()
        let signedOut = try Fixture()
        await signedOut.backup.backUpNow()
        signedOut.cloud.versions[0].uploaded = true
        signedOut.cloud.account = nil; signedOut.cloud.onChange?(); try await drain()
        expect(signedOut.backup.lastUploadConfirmed == nil, "Sign-out rejects stale uploaded metadata even when both account states become nil")
        if case .error = signedOut.backup.status { count += 1 } else { preconditionFailure("Account error must remain visible after sign-out") }
        try await signedOut.clean()

        let marker = try Fixture()
        let faults = FaultFiles(root: marker.root.appendingPathComponent("faults"))
        let faultTransaction = BackupRestoreTransaction(defaults: marker.defaults, domain: marker.suite, disk: faults)
        let target = Dictionary(uniqueKeysWithValues: BackupRestoreTransaction.keys.map { ($0, Data("new-\($0)".utf8)) })
        let markerJournal = try faultTransaction.originalJournal(candidate: target)
        await faults.configure(commit: true)
        do { try await faultTransaction.apply(markerJournal); preconditionFailure("Injected commit failure must surface") } catch { count += 1 }
        expect(BackupRestoreTransaction.keys.allSatisfy { marker.defaults.data(forKey: $0) == target[$0] }, "Never roll back after a commit marker may already be durable")
        try faultTransaction.recoverBeforeLoading()
        expect(BackupRestoreTransaction.keys.allSatisfy { marker.defaults.data(forKey: $0) == target[$0] }, "Startup preserves the complete committed candidate after marker failure")
        try await marker.clean()

        let recoveryFailure = try Fixture()
        await recoveryFailure.backup.backUpNow()
        let recoveryFaults = FaultFiles(root: recoveryFailure.root.appendingPathComponent("failed-recovery"))
        await recoveryFaults.configure(recovery: true)
        let recoveryTransaction = BackupRestoreTransaction(defaults: recoveryFailure.defaults, domain: recoveryFailure.suite, disk: recoveryFaults)
        let recoveryModel = BackupModel(workspace: recoveryFailure.workspace, tasks: recoveryFailure.tasks, habits: recoveryFailure.habits, preferences: recoveryFailure.preferences, music: recoveryFailure.music, gate: recoveryFailure.gate, cloud: recoveryFailure.cloud, transaction: recoveryTransaction, defaults: recoveryFailure.defaults)
        await recoveryModel.prepareRestore(recoveryFailure.cloud.versions[0])
        let originalWorkspace = recoveryFailure.defaults.data(forKey: "keep.timesheet.v1")
        await recoveryModel.restore()
        expect(recoveryFailure.defaults.data(forKey: "keep.timesheet.v1") == originalWorkspace && !recoveryFailure.gate.isLocked && recoveryModel.preview != nil, "Failed recovery-copy creation never replaces live archives")
        try await recoveryFailure.clean()

        let history = try Fixture()
        var ledger = TimesheetLedger()
        let calendar = Calendar(identifier: .gregorian), completionDate = Date.now
        ledger.beginPomodoroHistory(at: completionDate.addingTimeInterval(-3600))
        let completion = CompletedPomodoro(id: UUID(), project: FocusProject.defaults[0], task: "Finished focus", completedAt: completionDate, dayID: TimesheetWeek.dayID(for: completionDate, calendar: calendar), timeZoneID: calendar.timeZone.identifier, focusDuration: 1500)
        ledger.recordCompletion(completion)
        let custom = FocusProject(id: UUID().uuidString, name: "Deleted project", accent: .sage, category: "Custom")
        ledger.registerProject(custom); ledger.deleteProject(id: custom.id)
        let builtIn = FocusProject.defaults[0]
        ledger.updateProject(FocusProject(id: builtIn.id, name: "Renamed Keep", accent: .sage, category: builtIn.category))
        let snapshot = BackupPayload(workspace: ledger, tasks: TaskArchive(), habits: HabitArchive(), settings: PortableSettings(SettingsArchive()))
        let historyEnvelope = try await history.transaction.disk.prepare(snapshot, deviceID: UUID(), date: .now, appVersion: "1")
        let historyReload = try historyEnvelope.validatedPayload()
        expect(historyReload.workspace.completedPomodoros.first?.id == completion.id && historyReload.workspace.pomodoroHistoryStartedAt == ledger.pomodoroHistoryStartedAt, "Completion events and coverage round trip without inference")
        expect(historyReload.workspace.deletedProjectIDs.contains(custom.id) && historyReload.workspace.projectOverrides.first?.name == "Renamed Keep", "Catalog deletion and overrides survive backup")
        expect(historyReload.summary.hasPrefix("4 projects"), "Restore preview counts only active projects")
        try await history.clean()
        let cancel = try Fixture()
        await cancel.backup.backUpNow(); cancel.cloud.holdRead = true
        let opening = Task { await cancel.backup.prepareRestore(cancel.cloud.versions[0]) }
        for _ in 0..<100 {
            if cancel.cloud.readContinuation != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        opening.cancel(); cancel.backup.cancelPreview(); cancel.cloud.readContinuation?.resume(); await opening.value
        expect(cancel.backup.preview == nil && cancel.backup.restoreActivity == nil && !cancel.backup.busy, "Canceling a download cannot publish a late preview")
        try await cancel.clean()

        let queue = try Fixture()
        await queue.backup.setAutomatic(true); await queue.backup.backUpNow()
        await queue.backup.setAutomatic(false)
        expect(FileManager.default.fileExists(atPath: queue.root.appendingPathComponent("Outbox/queued.keepbackup").path), "Disabling automatic backup preserves explicitly requested queued work")
        queue.cloud.confirm(); try await drain(); await queue.backup.retryPending()
        expect(queue.cloud.submissions.count == 2, "Manual queued snapshot uploads with automatic backup off")
        await queue.backup.setAutomatic(true)
        _ = queue.tasks.add("Automatic queued change", on: day)
        queue.clock.date += 3600; await queue.backup.tick()
        expect(queue.backup.localState.queuedIsAutomatic == true, "Automatic queued origin is tracked separately")
        await queue.backup.setAutomatic(false)
        expect(!FileManager.default.fileExists(atPath: queue.root.appendingPathComponent("Outbox/queued.keepbackup").path), "Disabling automatic backup discards new automatic submissions")
        try await queue.clean()
        let legacyRestore = try Fixture()
        await legacyRestore.backup.backUpNow()
        let oldPayload = BackupPayload(workspace: TimesheetLedger(), tasks: TaskArchive(), habits: HabitArchive(), settings: PortableSettings(SettingsArchive()))
        let oldEnvelope = try await legacyRestore.transaction.disk.prepare(oldPayload, deviceID: UUID(), date: .now, appVersion: "1")
        _ = try await legacyRestore.cloud.submit(legacyRestore.transaction.disk.encode(oldEnvelope), envelope: oldEnvelope)
        await legacyRestore.backup.prepareRestore(legacyRestore.cloud.versions.last ?? legacyRestore.cloud.versions[0])
        await legacyRestore.backup.restore()
        expect(legacyRestore.workspace.ledger.pomodoroHistoryStartedAt == legacyRestore.clock.date, "Legacy restore begins tracking coverage without inventing completion events")
        let instant = ContinuousClock.now
        legacyRestore.workspace.play(.pomodoro, at: instant, date: legacyRestore.clock.date)
        legacyRestore.workspace.synchronize(at: instant.advanced(by: .seconds(1500)), date: legacyRestore.clock.date.addingTimeInterval(1500))
        let savedHistory = try TimesheetPersistence(defaults: legacyRestore.defaults).load()
        expect(savedHistory.completedPomodoros.count == 1 && savedHistory.pomodoroHistoryStartedAt != nil, "A completion after legacy restore remains a valid reloadable archive")
        try await legacyRestore.clean()
        let cleanup = try Fixture()
        await cleanup.backup.backUpNow()
        let removalFault = FaultFiles(root: cleanup.root)
        let removalTransaction = BackupRestoreTransaction(defaults: cleanup.defaults, domain: cleanup.suite, disk: removalFault)
        let cleanupModel = BackupModel(workspace: cleanup.workspace, tasks: cleanup.tasks, habits: cleanup.habits, preferences: cleanup.preferences, music: cleanup.music, gate: cleanup.gate, cloud: cleanup.cloud, transaction: removalTransaction, defaults: cleanup.defaults)
        cleanupModel.start(); try await drain()
        await removalFault.configure(removal: true)
        cleanup.cloud.account = Data("new-account".utf8); cleanup.cloud.onChange?(); try await drain()
        let submissionsBeforeCleanup = cleanup.cloud.submissionCalls
        await cleanupModel.backUpNow()
        expect(cleanup.cloud.submissionCalls == submissionsBeforeCleanup && cleanupModel.localState.account == nil, "Failed old-outbox cleanup cannot adopt or upload into a new account")
        await removalFault.configure()
        await cleanupModel.backUpNow()
        expect(cleanup.cloud.submissionCalls == submissionsBeforeCleanup + 1, "New account receives only a freshly captured, explicitly requested snapshot after cleanup")
        cleanupModel.stop(); try await cleanup.clean()
        let identity = "same-account" as NSString
        let binaryIdentity = try NSKeyedArchiver.archivedData(withRootObject: identity, requiringSecureCoding: false)
        let xmlArchive = NSKeyedArchiver(requiringSecureCoding: false); xmlArchive.outputFormat = .xml
        xmlArchive.encode(identity, forKey: NSKeyedArchiveRootObjectKey); xmlArchive.finishEncoding()
        expect(binaryIdentity != xmlArchive.encodedData, "Identity fixture has different archive representations")
        expect(ICloudBackupIdentity.matches(xmlArchive.encodedData, token: identity), "Opaque identity comparison uses isEqual rather than archive-byte equality")
        expect(!ICloudBackupIdentity.matches(binaryIdentity, token: "different-account" as NSString), "Different opaque identities never match")
        expect(!ICloudBackupIdentity.matches(nil, token: identity), "Missing stored identity never authorizes account transfers")
        expect(!ICloudBackupIdentity.matches(Data("invalid archive".utf8), token: identity), "Malformed identity archives fail closed")
        let uploadErrors = try Fixture()
        uploadErrors.cloud.failWrites = true
        await uploadErrors.backup.backUpNow()
        let pendingEnvelope = try await uploadErrors.transaction.disk.validatedEnvelope(uploadErrors.transaction.disk.read(uploadErrors.root.appendingPathComponent("Outbox/active.keepbackup")))
        expect(uploadErrors.cloud.submissions.isEmpty && uploadErrors.backup.lastUploadConfirmed == nil, "Failed cloud submission keeps a durable pending file without claiming success")
        uploadErrors.cloud.failWrites = false; await uploadErrors.backup.retryPending()
        expect(uploadErrors.cloud.submissions[pendingEnvelope.id] != nil, "Retry reuses the same backup ID")
        uploadErrors.cloud.confirm(); try await drain()
        let confirmedBeforeError = uploadErrors.backup.lastUploadConfirmed
        uploadErrors.clock.date += 60; await uploadErrors.backup.backUpNow()
        let index = uploadErrors.cloud.versions.count - 1
        uploadErrors.cloud.versions[index].error = "iCloud storage is full. Free space and retry."
        uploadErrors.cloud.onChange?(); try await drain()
        expect(uploadErrors.backup.status == .error("iCloud storage is full. Free space and retry."), "Quota/upload metadata errors remain actionable")
        expect(uploadErrors.backup.lastUploadConfirmed == confirmedBeforeError, "Later upload errors preserve the last successful confirmation")
        uploadErrors.cloud.versions[index].error = nil; uploadErrors.cloud.versions[index].uploading = true
        uploadErrors.cloud.onChange?(); try await drain()
        expect(uploadErrors.backup.status == .uploading, "Uploading is distinct from local creation and confirmed upload")
        uploadErrors.cloud.confirm(); try await drain()
        expect(uploadErrors.backup.status == .uploaded && uploadErrors.backup.lastUploadConfirmed == uploadErrors.clock.date, "Manual backup completion remains visible with automatic backup off")
        try await uploadErrors.clean()
        try retention()
        print("Passed \(count) backup checks")
    }
    static func retention() throws {
        let device = UUID(), other = UUID(), date = Date(timeIntervalSince1970: 1_791_374_400)
        var versions: [BackupVersion] = []
        for day in 0..<45 {
            for hour in 0..<3 {
                versions.append(BackupVersion(url: URL(fileURLWithPath: "/\(day)-\(hour)"), createdAt: date.addingTimeInterval(-Double(day * 86400 + hour * 3600)), deviceID: device.uuidString, uploaded: true))
            }
        }
        let foreign = BackupVersion(url: URL(fileURLWithPath: "/foreign"), createdAt: .distantPast, deviceID: other.uuidString, uploaded: true)
        let pending = BackupVersion(url: URL(fileURLWithPath: "/pending"), createdAt: .distantPast, deviceID: device.uuidString)
        versions += [foreign, pending]
        let removed = BackupRetention.removals(versions, deviceID: device, now: date)
        let kept = versions.filter { !removed.contains($0) }
        expect(!removed.contains(foreign) && !removed.contains(pending), "Never prune another Mac or a pending upload")
        expect(kept.count > 24 && kept.count <= 56, "Keep union of latest 24 and daily versions")
        let latest24 = versions.filter { $0.deviceID == device.uuidString && $0.uploaded }.sorted { $0.createdAt > $1.createdAt }.prefix(24)
        expect(latest24.allSatisfy { kept.contains($0) }, "Latest 24 always retained")
        for day in 0..<30 {
            expect(kept.contains { $0.url.path == "/\(day)-0" }, "Newest version for each of 30 UTC days retained")
        }
        expect(removed.contains { $0.url.path == "/44-0" }, "Older versions pruned")
    }
}

/// Exercises file-adapter failures, including an error after an atomic commit marker write.
private actor FaultFiles: BackupFileStorage {
    nonisolated let root: URL
    private let base: BackupLocalFiles
    var failRecovery = false
    var failAfterCommit = false
    var failRemoval = false
    init(root: URL) { self.root = root; base = BackupLocalFiles(root: root) }
    func configure(recovery: Bool = false, commit: Bool = false, removal: Bool = false) { failRecovery = recovery; failAfterCommit = commit; failRemoval = removal }
    func encode<T: Encodable>(_ value: T) async throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value) }
    func decode<T: Decodable>(_ type: T.Type, data: Data) async throws -> T { try JSONDecoder().decode(type, from: data) }
    func prepare(_ payload: BackupPayload, deviceID: UUID, date: Date, appVersion: String) async throws -> BackupEnvelope { try await base.prepare(payload, deviceID: deviceID, date: date, appVersion: appVersion) }
    func validatedEnvelope(_ data: Data) async throws -> BackupEnvelope { try await base.validatedEnvelope(data) }
    func payload(_ envelope: BackupEnvelope) async throws -> BackupPayload { try await base.payload(envelope) }
    func exists(_ url: URL) async -> Bool { await base.exists(url) }
    func read(_ url: URL) async throws -> Data { try await base.read(url) }
    func write(_ data: Data, to url: URL) async throws {
        if failRecovery && url.deletingLastPathComponent().lastPathComponent == "Recovery" { throw BackupFailure.writeFailed }
        try await base.write(data, to: url)
        if failAfterCommit && url.lastPathComponent == "restore-journal.json", try await base.decode(RestoreJournal.self, data: data).committed { throw BackupFailure.writeFailed }
    }
    func remove(_ url: URL) async throws { if failRemoval { throw BackupFailure.writeFailed }; try await base.remove(url) }
    func recoveryFiles() async throws -> [URL] { try await base.recoveryFiles() }
    func pruneRawRecovery(keeping count: Int) async throws { try await base.pruneRawRecovery(keeping: count) }
}
