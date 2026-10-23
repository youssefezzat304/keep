import AppKit
import Foundation

private actor FaultDisk: BackupFileStorage {
    nonisolated let root: URL
    let base: BackupLocalFiles
    var failRecovery = false
    var corruptRecovery = false
    init(root: URL) { self.root = root; base = BackupLocalFiles(root: root) }
    func configure(fail: Bool = false, corrupt: Bool = false) { failRecovery = fail; corruptRecovery = corrupt }
    func encode<T: Encodable>(_ value: T) async throws -> Data { try JSONEncoder().encode(value) }
    func decode<T: Decodable>(_ type: T.Type, data: Data) async throws -> T { try JSONDecoder().decode(type, from: data) }
    func prepare(_ payload: BackupPayload, deviceID: UUID, date: Date, appVersion: String) async throws -> BackupEnvelope { try await base.prepare(payload, deviceID: deviceID, date: date, appVersion: appVersion) }
    func validatedEnvelope(_ data: Data) async throws -> BackupEnvelope { try await base.validatedEnvelope(data) }
    func payload(_ envelope: BackupEnvelope) async throws -> BackupPayload { try await base.payload(envelope) }
    func exists(_ url: URL) async -> Bool { await base.exists(url) }
    func read(_ url: URL) async throws -> Data {
        if corruptRecovery && url.path.contains("ImportRecovery") { return Data("damaged".utf8) }
        return try await base.read(url)
    }
    func write(_ data: Data, to url: URL) async throws {
        if failRecovery && url.path.contains("ImportRecovery") { throw CocoaError(.fileWriteOutOfSpace) }
        try await base.write(data, to: url)
    }
    func remove(_ url: URL) async throws { try await base.remove(url) }
    func recoveryFiles() async throws -> [URL] { try await base.recoveryFiles() }
    func pruneRawRecovery(keeping count: Int) async throws { try await base.pruneRawRecovery(keeping: count) }
}

private final class ImportFixture {
    let suite = "keep.import.checks.\(UUID().uuidString)"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("keep-import-checks-\(UUID().uuidString)")
    let defaults: UserDefaults
    let disk: FaultDisk
    let gate = BackupRestoreGate()
    let transaction: BackupRestoreTransaction
    let workspace: WorkspaceModel
    let tasks: DailyTaskStore
    let habits: HabitStore
    let preferences: AppPreferences
    let model: ImportCoordinator
    let calendar: Calendar
    var capture: SnapshotCapture { .init(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, gate: gate) }
    init() throws {
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }; self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt; self.calendar = calendar
        disk = FaultDisk(root: root)
        transaction = BackupRestoreTransaction(defaults: defaults, domain: suite, disk: disk)
        var wp = TimesheetPersistence(defaults: defaults); wp.access = gate
        var tp = TaskPersistence(defaults: defaults); tp.access = gate
        var hp = HabitPersistence(defaults: defaults); hp.access = gate
        var sp = SettingsPersistence(defaults: defaults); sp.access = gate
        preferences = AppPreferences(persistence: sp); habits = HabitStore(persistence: hp, calendar: calendar)
        tasks = DailyTaskStore(persistence: tp, calendar: calendar, habits: habits)
        workspace = WorkspaceModel(persistence: wp, calendar: calendar, timerPreferences: preferences, tasks: tasks, habits: habits)
        model = ImportCoordinator(capture: .init(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, gate: gate), gate: gate, transaction: transaction)
    }
    func open(_ payload: KeepDataPayload) async throws {
        let url = root.appendingPathComponent("input.keepdata")
        try await disk.write(try await disk.encode(KeepDataEnvelope(payload, date: .now, appVersion: "checks")), to: url)
        model.open(url); try await ImportChecks.settle(model)
    }
    func clean() throws {
        model.cancel(); workspace.shutdown(); defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
}

@main enum ImportChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func rejects(_ message: String, _ action: () throws -> Void) {
        do { try action(); preconditionFailure(message) } catch { checks += 1 }
    }
    static func settle(_ model: ImportCoordinator) async throws {
        for _ in 0..<500 { if !model.phase.busy { return }; try await Task.sleep(for: .milliseconds(10)) }
        preconditionFailure("Import did not settle")
    }
    static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = .gmt; return value }
    static func date(_ day: String, hour: Int = 12) -> Date { calendar.startOfDay(for: TaskDay.date(for: day, calendar: calendar) ?? .distantPast).addingTimeInterval(Double(hour * 3600)) }
    static func payload(_ ledger: TimesheetLedger = .init(), tasks: TaskArchive = .init(), habits: HabitArchive = .init(), settings: SettingsArchive = .init()) -> KeepDataPayload {
        KeepDataPayload(backup: .init(workspace: ledger, tasks: tasks, habits: habits, settings: PortableSettings(settings)), timeZone: "UTC")
    }
    static func main() async throws {
        _ = NSApplication.shared
        do {
            try archiveChecks()
            try mergeChecks()
            try additionalMergeChecks()
            try await fileChecks()
            try await transactionChecks()
            try await interruptedAndTimerChecks()
            try await habitInstallationChecks()
        } catch { preconditionFailure("Import checks failed after \(checks) checks: \(error)") }
        print("Passed \(checks) data archive, merge, import safety and recovery checks")
    }
    static func archiveChecks() throws {
        var ledger = TimesheetLedger()
        let project = FocusProject(id: "custom", name: "Étude 日本語", accent: .sage, category: "Study")
        ledger.registerProject(project); ledger.setProjectTargets(.init(goal: 90, minimum: 30), projectID: project.id)
        ledger.record(project: project, from: date("2026-10-01"), seconds: 600, calendar: calendar, sessionID: UUID(), task: "Notes\nwith Unicode 🦉", source: .flow)
        ledger.setSeconds(100, project: project, dayID: "2026-10-01")
        ledger.beginPomodoroHistory(at: date("2026-09-01"))
        ledger.recordCompletion(.init(id: UUID(), project: project, task: "Read", completedAt: date("2026-10-01"), dayID: "2026-10-01", timeZoneID: "UTC", focusDuration: 1500))
        ledger.rememberTask("Pinned", project: project, date: date("2026-10-01"))
        if let activity = ledger.taskActivities.first { ledger.toggleTaskPin(id: activity.id) }
        ledger.setPomodoroSettings(.defaults)
        var settings = SettingsArchive(); settings.appearance = .dark; settings.musicVolume = 0.1
        settings.weeklyFocusGoalMinutes = 120
        guard let url = URL(string: "https://audius.co/artist") else { throw CocoaError(.coderInvalidValue) }
        settings.channels = [.init(resourceID: "abc", name: "Artist", kind: .artist, url: url)]
        let habit = Habit(id: UUID(), name: "Read", icon: .book, startDay: "2026-09-01", endDay: nil, goal: .amount(target: 10, unit: .minutes), weeklyTargets: .init(goal: 60, minimum: 30))
        let countedHabit = Habit(id: UUID(), name: "Water", icon: .water, startDay: "2026-09-01", endDay: nil, goal: .amount(target: 5, unit: .times))
        let tasks = TaskArchive(days: ["2027-01-01": [FocusTask(title: "Future", isComplete: true, estimateMinutes: 30)]], hiddenHabitIDs: ["2026-10-01": [habit.id]])
        let habits = HabitArchive(habits: [habit, countedHabit], logs: [.init(habitID: habit.id, dayID: "2026-10-01", amount: 10), .init(habitID: countedHabit.id, dayID: "2026-10-01", amount: 2)], consumedTimerGoals: [habit.id: ["2026-10-01"]])
        let data = payload(ledger, tasks: tasks, habits: habits, settings: settings)
        let envelope = try KeepDataEnvelope(data, date: .now, appVersion: "checks")
        let encoded = try JSONEncoder().encode(envelope)
        expect(try KeepDataEnvelope.decode(encoded) == data, "All tracked values round-trip losslessly")
        let text = String(decoding: envelope.payload, as: UTF8.self)
        for excluded in ["appearance", "pomodoroSettings", "pomodoroPresets", "musicVolume", "folderBookmark", "selectedChannelID", "dashboardPage", "notchFlowTimer"] {
            expect(!text.contains("\"" + excluded + "\""), "Configuration is excluded: " + excluded)
        }
        expect(text.contains("weeklyFocusGoalMinutes") && text.contains("channels"), "Goals and saved channels are explicitly included")
        var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        object["checksum"] = "wrong"
        rejects("Damaged checksum rejected") { _ = try KeepDataEnvelope.decode(JSONSerialization.data(withJSONObject: object)) }
        object["schemaVersion"] = 99
        rejects("Future version rejected") { _ = try KeepDataEnvelope.decode(JSONSerialization.data(withJSONObject: object)) }
        let empty = payload()
        expect(try KeepDataEnvelope.decode(JSONEncoder().encode(KeepDataEnvelope(empty, date: .now, appVersion: "checks"))) == empty, "Empty archives round-trip")
        let snapshot = PersistentSnapshot(workspace: ledger, tasks: tasks, habits: habits, settings: PortableSettings(settings), projects: [], capturedAt: .now, calendar: calendar)
        let request = ExportRequest(data: .all, from: date("2027-01-02"), through: date("2027-01-01"), projectID: "ignored", taskKeys: ["ignored"])
        let report = try ExportReports.make(request, snapshot: snapshot)
        expect(report.count == 1 && report[0].filename.hasSuffix(".keepdata"), "Export all ignores filters and makes a portable file")
        expect(try KeepDataEnvelope.decode(report[0].contents) == KeepDataPayload(snapshot), "Export all contains the complete data set")
    }
    static func mergeChecks() throws {
        let project = FocusProject.defaults[0]
        var base = TimesheetLedger()
        let firstID = UUID(), secondID = UUID()
        base.record(project: project, from: date("2026-10-01"), seconds: 600, calendar: calendar, sessionID: firstID, task: "First")
        base.setSeconds(100, project: project, dayID: "2026-10-01")
        var source = base
        source.record(project: project, from: date("2026-10-01", hour: 14), seconds: 120, calendar: calendar, sessionID: secondID, task: "Second")
        let local = payload(base), incoming = payload(source)
        let merged = try ImportMerge.review(source: incoming, local: local, scope: .all)
        expect(merged.canApply && merged.candidate.workspace.sessions.count == 2, "Missing sessions are added")
        expect(merged.candidate.workspace.entries.first?.seconds == 220, "Negative manual correction is preserved without double-counting")
        let repeated = try ImportMerge.review(source: incoming, local: merged.candidate, scope: .all)
        expect(!repeated.hasChanges, "Reimport is idempotent")
        var correction = incoming; correction.workspace.entries[0].seconds = 800
        let corrected = try ImportMerge.review(source: correction, local: merged.candidate, scope: .all)
        expect(corrected.replacements == 1 && corrected.issues.contains { $0.id.hasPrefix("adjustment/") }, "Conflicting correction is reviewed separately")
        expect(corrected.candidate.workspace.entries[0].seconds == 800, "Imported correction wins only in candidate")
        var decisions = ImportDecisions(); decisions.resolutions["adjustment/keep/2026-10-01"] = .local
        expect(try ImportMerge.review(source: correction, local: merged.candidate, scope: .all, decisions: decisions).candidate.workspace.entries[0].seconds == 220, "User can retain local correction")
        var overlapLedger = TimesheetLedger()
        overlapLedger.record(project: project, from: date("2026-10-01").addingTimeInterval(60), seconds: 180, calendar: calendar, sessionID: UUID(), task: "Overlap")
        let overlap = payload(overlapLedger)
        let pending = try ImportMerge.review(source: overlap, local: local, scope: .all)
        guard let issue = pending.issues.first(where: { $0.id.hasPrefix("overlap/") }) else { preconditionFailure("No overlap issue") }
        expect(!pending.canApply, "Different-ID overlaps require an explicit choice")
        for (choice, count) in [(ImportResolution.local, 1), (.incoming, 1), (.both, 2)] {
            decisions = .init(); decisions.resolutions[issue.id] = choice
            let review = try ImportMerge.review(source: overlap, local: local, scope: .all, decisions: decisions)
            expect(review.blockers.isEmpty && review.candidate.workspace.sessions.count == count, "Overlap resolution: " + choice.rawValue)
            if choice == .incoming { expect(review.candidate.workspace.sessions.first?.task == "Overlap", "Use imported removes listed local sessions") }
        }

        let localHabit = Habit(id: UUID(), name: "Reading habit", icon: .book, startDay: "2026-09-01", endDay: nil, goal: .checkIn)
        let foreignHabit = Habit(id: UUID(), name: "READING HABIT", icon: .book, startDay: "2026-09-01", endDay: nil, goal: .checkIn)
        var habitLocal = payload(habits: .init(habits: [localHabit]))
        var habitSource = payload(habits: .init(habits: [foreignHabit], logs: [.init(habitID: foreignHabit.id, dayID: "2026-10-01", amount: 1)]))
        let nameReview = try ImportMerge.review(source: habitSource, local: habitLocal, scope: .all)
        let nameID = "name/habit/" + foreignHabit.id.uuidString
        expect(nameReview.issues.contains { $0.id == nameID } && !nameReview.canApply, "Matching names with different IDs require review")
        decisions = .init(); decisions.resolutions[nameID] = .link
        let linked = try ImportMerge.review(source: habitSource, local: habitLocal, scope: .all, decisions: decisions)
        expect(linked.candidate.habits.habits.count == 1 && linked.candidate.habits.logs[0].habitID == localHabit.id, "Linking remaps habit history")
        decisions.resolutions[nameID] = .both
        expect(try !ImportMerge.review(source: habitSource, local: habitLocal, scope: .all, decisions: decisions).canApply, "Keep both requires a unique name")
        decisions.names[nameID] = "Reading on another Mac"
        let separate = try ImportMerge.review(source: habitSource, local: habitLocal, scope: .all, decisions: decisions)
        expect(separate.canApply && separate.candidate.habits.habits.count == 2, "Keep both retains distinct renamed definitions")

        let task = FocusTask(title: "Linked future task", estimateMinutes: 20)
        habitSource.tasks.days = ["2027-01-01": [task]]
        var sessionLedger = TimesheetLedger()
        sessionLedger.record(project: project, from: date("2026-10-01"), seconds: 60, calendar: calendar, sessionID: UUID(), task: task.title, taskReference: .task(id: task.id, dayID: "2027-01-01"))
        habitSource.workspace = TrackedWorkspace(sessionLedger)
        habitSource.channels = [.init(resourceID: "xyz", name: "Saved", kind: .artist, url: URL(string: "https://audius.co/saved") ?? URL(fileURLWithPath: "/"))]
        let period = ImportScope.dates(from: "2026-10-01", through: "2026-10-01")
        let periodReview = try ImportMerge.review(source: habitSource, local: payload(), scope: period)
        expect(periodReview.candidate.tasks.days["2027-01-01"]?.first == task, "Missing linked tasks outside dates are supporting definitions")
        expect(periodReview.candidate.channels.isEmpty && periodReview.candidate.habits.habits.count == 1, "Period import includes scheduled habits and excludes channels")
        var edited = task; edited.title = "Keep local future task"
        var withExisting = payload(); withExisting.tasks.days["2027-01-01"] = [edited]
        let preserve = try ImportMerge.review(source: habitSource, local: withExisting, scope: period)
        expect(preserve.candidate.tasks.days["2027-01-01"] == [edited], "Existing outside-period task state is preserved")
        rejects("Inverted range rejected") { _ = try ImportMerge.review(source: incoming, local: local, scope: .dates(from: "2026-10-02", through: "2026-10-01")) }

        habitLocal.habits.logs = [.init(habitID: localHabit.id, dayID: "2026-09-15", amount: 1)]
        let incompatible = Habit(id: localHabit.id, name: localHabit.name, icon: .book, startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        let invalid = payload(habits: .init(habits: [incompatible]))
        let invalidReview = try ImportMerge.review(source: invalid, local: habitLocal, scope: period)
        expect(!invalidReview.canApply && !invalidReview.blockers.isEmpty, "Definition cannot invalidate retained history")
        decisions = .init(); decisions.resolutions["Habits/" + localHabit.id.uuidString] = .local
        expect(try ImportMerge.review(source: invalid, local: habitLocal, scope: period, decisions: decisions).blockers.isEmpty, "Keeping local definition resolves invalid history")
    }
    static func fileChecks() async throws {
        let fixture = try ImportFixture(); defer { do { try fixture.clean() } catch { preconditionFailure("Fixture cleanup failed: \(error)") } }
        let files = ImportFiles(disk: fixture.disk)
        do { _ = try await files.open(fixture.root.appendingPathComponent("report.csv"), timeZone: "UTC"); preconditionFailure("CSV accepted") }
        catch ImportFailure.unsupportedFile { checks += 1 }
        let snapshot = try fixture.capture.capture(.backup)
        let data = try KeepDataPayload(snapshot)
        let url = try await files.saveRecovery(data, date: .now)
        expect(try await files.open(url, timeZone: "UTC") == data, "Verified recovery is importable")
        let legacyRecoveries = try await fixture.disk.recoveryFiles()
        expect(url.path.contains("ImportRecovery") && legacyRecoveries.isEmpty, "Recovery is outside iCloud restore pruning")
        let backupURL = fixture.root.appendingPathComponent("legacy.keepbackup")
        try await fixture.disk.write(try await fixture.disk.encode(BackupEnvelope(snapshot: snapshot.backupPayload(), deviceID: UUID(), date: .now, appVersion: "checks")), to: backupURL)
        expect(try await files.open(backupURL, timeZone: data.reportingTimeZone) == data, "Existing backups convert to data-only archives")
        await fixture.disk.configure(corrupt: true)
        do { _ = try await files.saveRecovery(data, date: .now); preconditionFailure("Corrupt recovery accepted") } catch { checks += 1 }
        await fixture.disk.configure()
        let link = fixture.root.appendingPathComponent("link.keepdata")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        do { _ = try await files.open(link, timeZone: "UTC"); preconditionFailure("Symbolic link accepted") } catch { checks += 1 }
    }
    static func additionalMergeChecks() throws {
        let project = FocusProject.defaults[0]
        var ledger = TimesheetLedger()
        ledger.record(project: project, from: date("2026-10-01"), seconds: 120, calendar: calendar, sessionID: UUID(), task: "Before")
        ledger.record(project: project, from: date("2026-10-02"), seconds: 60, calendar: calendar, sessionID: UUID(), task: "Selected")
        ledger.record(project: project, from: date("2026-10-03"), seconds: 120, calendar: calendar, sessionID: UUID(), task: "After")
        ledger.setSeconds(180, project: project, dayID: "2026-10-02")
        let selected = ImportScope.dates(from: "2026-10-02", through: "2026-10-02")
        let range = try ImportMerge.review(source: payload(ledger), local: payload(), scope: selected)
        expect(range.candidate.workspace.sessions.map(\.task) == ["Selected"], "Both date boundaries are inclusive and surrounding days excluded")
        expect(range.candidate.workspace.entries.first?.seconds == 180, "Positive untimed correction survives a period import")
        var moved = payload(ledger)
        let old = moved.workspace.sessions[0]
        moved.workspace.sessions[0] = .init(id: old.id, recordingID: old.recordingID, dayID: "2026-10-02", project: old.project, task: old.task, source: old.source, timeZoneID: "UTC", start: date("2026-10-02", hour: 14), end: date("2026-10-02", hour: 14).addingTimeInterval(120))
        let outside = try ImportMerge.review(source: moved, local: payload(ledger), scope: selected)
        expect(outside.issues.contains { $0.id == "Sessions/" + old.id && $0.choices == [.local] }, "Same-ID moves cannot overwrite a record outside selected dates")
        expect(outside.candidate.workspace.sessions.contains(old), "Outside-period original session remains intact")

        var berlin = calendar; berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        var dst = TimesheetLedger()
        guard let start = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0)) else { throw ImportFailure.invalidRange }
        dst.record(project: project, from: start, seconds: 25 * 3600, calendar: berlin, sessionID: UUID())
        let dstReview = try ImportMerge.review(source: payload(dst), local: payload(), scope: .dates(from: "2026-10-25", through: "2026-10-25"))
        expect(dstReview.candidate.workspace.sessions.first?.seconds == 25 * 3600 && dstReview.candidate.workspace.sessions.first?.timeZoneID == "Europe/Berlin", "DST civil day remains a 25-hour recorded day")

        var source = payload(), local = payload()
        source.weeklyFocusGoalMinutes = 200; local.weeklyFocusGoalMinutes = 90
        let goal = try ImportMerge.review(source: source, local: local, scope: selected)
        expect(goal.replacements == 1 && goal.candidate.weeklyFocusGoalMinutes == 200, "Global goal is content even in a date import")
        source.weeklyFocusGoalMinutes = nil
        expect(try ImportMerge.review(source: source, local: local, scope: .all).candidate.weeklyFocusGoalMinutes == nil, "An explicit unset goal can replace an existing goal after review")
        var deleted = TimesheetLedger(); deleted.deleteProject(id: project.id)
        let status = try ImportMerge.review(source: payload(deleted), local: payload(), scope: .all)
        expect(status.candidate.workspace.deletedProjectIDs.contains(project.id) && status.issues.contains { $0.id == "project-status/" + project.id }, "Explicit project deletion status is reviewed")

        let custom = FocusProject(id: UUID().uuidString, name: project.name, accent: .sage, category: "Imported")
        var foreign = TimesheetLedger(); foreign.registerProject(custom); foreign.deleteProject(id: project.id)
        foreign.record(project: custom, from: date("2026-10-01"), seconds: 60, calendar: calendar, sessionID: UUID(), task: "Linked")
        let nameID = "name/project/" + custom.id
        var decisions = ImportDecisions(); decisions.resolutions[nameID] = .link
        let link = try ImportMerge.review(source: payload(foreign), local: payload(), scope: .all, decisions: decisions)
        expect(link.candidate.workspace.sessions.first?.project.id == project.id, "Project linking remaps session attribution")

        var suggestionLedger = TimesheetLedger()
        suggestionLedger.rememberTask("Same suggestion", project: project, date: date("2026-10-01"))
        let suggestion = payload(suggestionLedger)
        var sameKey = suggestion
        guard let activity = sameKey.workspace.taskActivities.first else { throw ImportFailure.invalidArchive }
        sameKey.workspace.taskActivities = [.init(id: UUID(), title: activity.title, project: activity.project, lastUsed: activity.lastUsed)]
        expect(try !ImportMerge.review(source: sameKey, local: suggestion, scope: .all).hasChanges, "Equivalent suggestions match by semantic key despite different IDs")

        // A full export often includes both shared sessions and a newly added overlap.
        // Shared IDs must not hide a different-ID collision or get re-added after removal.
        var common = TimesheetLedger()
        common.record(project: project, from: date("2026-10-01"), seconds: 600, calendar: calendar, sessionID: UUID(), task: "Shared")
        var commonPlusNew = common
        commonPlusNew.record(project: project, from: date("2026-10-01").addingTimeInterval(120), seconds: 120, calendar: calendar, sessionID: UUID(), task: "New overlap")
        let sharedReview = try ImportMerge.review(source: payload(commonPlusNew), local: payload(common), scope: .all)
        guard let sharedIssue = sharedReview.issues.first(where: { $0.id.hasPrefix("overlap/") }) else { preconditionFailure("Shared IDs hid the new overlap") }
        expect(!sharedReview.canApply, "Shared copies cannot hide a new overlapping session")
        var sharedChoices = ImportDecisions(); sharedChoices.resolutions[sharedIssue.id] = .incoming
        let replacement = try ImportMerge.review(source: payload(commonPlusNew), local: payload(common), scope: .all, decisions: sharedChoices)
        expect(replacement.candidate.workspace.sessions.map(\.task) == ["New overlap"], "An unchanged source copy cannot re-add a removed local overlap")
        expect(try !ImportMerge.review(source: payload(commonPlusNew), local: payload(commonPlusNew), scope: .all).hasChanges, "Already-known overlaps remain idempotent")

        var separated = TimesheetLedger()
        separated.record(project: project, from: date("2026-10-01"), seconds: 600, calendar: calendar, sessionID: UUID(), task: "A")
        separated.record(project: project, from: date("2026-10-01").addingTimeInterval(1200), seconds: 600, calendar: calendar, sessionID: UUID(), task: "B")
        var swapped = payload(separated)
        swapped.workspace.sessions[0] = try swapped.workspace.sessions[0].replacing(start: date("2026-10-01").addingTimeInterval(1200), end: date("2026-10-01").addingTimeInterval(1800))
        swapped.workspace.sessions[1] = try swapped.workspace.sessions[1].replacing(start: date("2026-10-01"), end: date("2026-10-01").addingTimeInterval(600))
        let swapReview = try ImportMerge.review(source: swapped, local: payload(separated), scope: .all)
        let swapIssues = swapReview.issues.filter { $0.id.hasPrefix("overlap/") }
        expect(swapIssues.count == 1, "Retimed identities join one coherent overlap group")
        if let issue = swapIssues.first {
            sharedChoices = .init(); sharedChoices.resolutions[issue.id] = .incoming
            let swapResult = try ImportMerge.review(source: swapped, local: payload(separated), scope: .all, decisions: sharedChoices)
            expect(swapResult.candidate.workspace.sessions == swapped.workspace.sessions, "Use imported retains both new versions in a crossed identity group")
        }

        let localHabitsProject = FocusProject(id: UUID().uuidString, name: "Habits", accent: .fern, category: "Habits")
        let foreignHabitsProject = FocusProject(id: UUID().uuidString, name: "Habits", accent: .fern, category: "Habits")
        var localHabitsLedger = TimesheetLedger(); localHabitsLedger.registerProject(localHabitsProject)
        var foreignHabitsLedger = TimesheetLedger(); foreignHabitsLedger.registerProject(foreignHabitsProject)
        foreignHabitsLedger.record(project: foreignHabitsProject, from: date("2026-10-01"), seconds: 60, calendar: calendar, sessionID: UUID())
        var mapping = ImportDecisions(); mapping.resolutions["name/project/" + foreignHabitsProject.id] = .link
        let habitProjectReview = try ImportMerge.review(source: payload(foreignHabitsLedger), local: payload(localHabitsLedger), scope: .all, decisions: mapping)
        expect(habitProjectReview.candidate.workspace.sessions.first?.project.id == localHabitsProject.id, "Habits project name links prefer the visible catalog over the hidden built-in fallback")
        var west = payload(), utc = payload()
        west.reportingTimeZone = "America/Los_Angeles"
        let dated = TaskActivity(id: UUID(), title: "Timezones", project: project, lastUsed: date("2026-10-02", hour: 1))
        west.workspace.taskActivities = [dated]
        var newer = dated; newer.lastUsed = date("2026-10-02", hour: 3); utc.workspace.taskActivities = [newer]
        let zones = try ImportMerge.review(source: utc, local: west, scope: selected)
        expect(zones.issues.contains { $0.id.hasPrefix("Suggestions/") && $0.choices == [.local] }, "Outside-period local suggestions use the local archive timezone")
        expect(zones.candidate.workspace.taskActivities == west.workspace.taskActivities, "Timezone filtering preserves the local out-of-period suggestion")

    }
    static func transactionChecks() async throws {
        for failure in ["none", "write", "verify", "commit"] {
            let fixture = try ImportFixture(); defer { do { try fixture.clean() } catch { preconditionFailure("Fixture cleanup failed: \(error)") } }
            fixture.preferences.appearance = .dark; fixture.preferences.musicVolume = 0.23
            let settingsBefore = fixture.preferences.snapshot
            var data = try KeepDataPayload(fixture.capture.capture(.backup))
            data.tasks.days["2027-01-01"] = [FocusTask(title: "Imported future plan")]
            data.weeklyFocusGoalMinutes = 100
            let before = try fixture.capture.capture(.backup)
            try await fixture.open(data)
            expect(fixture.model.canApply, "Valid candidate ready: " + failure)
            if failure == "write" { await fixture.disk.configure(fail: true) }
            if failure == "verify" { await fixture.disk.configure(corrupt: true) }
            if failure == "commit" { fixture.transaction.beforeWrite = { if $0 == 1 { throw CocoaError(.fileWriteOutOfSpace) } } }
            fixture.model.apply(); try await settle(fixture.model)
            if failure == "none" {
                expect(fixture.model.phase == .success && !fixture.gate.isLocked, "Successful transaction releases gate")
                expect(fixture.tasks.archive == data.tasks && fixture.preferences.weeklyFocusGoalMinutes == 100, "Committed content installed across owners")
                var expected = settingsBefore; expected.weeklyFocusGoalMinutes = 100
                expect(fixture.preferences.snapshot == expected, "All configuration stays unchanged")
                let reloaded = try TaskPersistence(defaults: fixture.defaults).load()
                expect(reloaded == data.tasks, "Imported data survives reload")
                guard let recovery = fixture.model.recoveryURL else { preconditionFailure("No recovery file") }
                let saved = try KeepDataEnvelope.decode(await fixture.disk.read(recovery))
                expect(saved == (try KeepDataPayload(before)), "Recovery contains the exact pre-import data")
                fixture.model.open(recovery); try await settle(fixture.model)
                expect(fixture.model.review?.candidate.tasks.days["2027-01-01"] != nil, "Recovery merging preserves newly added records")
            } else {
                expect(fixture.model.phase == .failed && !fixture.gate.isLocked, "Failure is reported and gate released: " + failure)
                expect(fixture.tasks.archive == before.tasks && fixture.preferences.snapshot == settingsBefore, "Failure changes no store values: " + failure)
                expect(try TaskPersistence(defaults: fixture.defaults).load() == before.tasks, "Failure preserves persisted data: " + failure)
                if failure != "commit" { expect(fixture.model.recoveryURL == nil, "No verified recovery means no commit") }
            }
        }
        let fixture = try ImportFixture(); defer { do { try fixture.clean() } catch { preconditionFailure("Fixture cleanup failed: \(error)") } }
        var data = try KeepDataPayload(fixture.capture.capture(.backup))
        data.tasks.days["2026-10-01"] = [FocusTask(title: "From archive")]
        try await fixture.open(data)
        _ = fixture.tasks.add("Changed while reviewing", on: "2026-10-02")
        fixture.model.apply(); try await settle(fixture.model)
        expect(fixture.model.phase == .reviewing && fixture.model.message?.contains("changed") == true, "Stale review requires confirmation again")
        expect(fixture.model.recoveryURL == nil && fixture.tasks.archive.days["2026-10-01"] == nil, "Stale review cannot back up or write an unapproved candidate")
        fixture.model.apply(); try await settle(fixture.model)
        expect(fixture.model.phase == .success && fixture.tasks.archive.days.count == 2, "Reconfirmed fresh merge preserves intervening changes")
        try await fixture.open(data)
        fixture.gate.generation = UUID()
        try await Task.sleep(for: .milliseconds(30))
        expect(fixture.model.source == nil && !fixture.model.canApply, "External restore invalidates app-owned import previews")
    }
    static func interruptedAndTimerChecks() async throws {
        let fixture = try ImportFixture()
        defer { do { try fixture.clean() } catch { preconditionFailure("Fixture cleanup failed: \(error)") } }
        var data = try KeepDataPayload(fixture.capture.capture(.backup))
        data.tasks.days["2027-01-01"] = [FocusTask(title: "Recoverable")]
        try await fixture.open(data)
        var syncs = 0
        fixture.transaction.synchronize = { syncs += 1; return syncs == 1 }
        fixture.model.apply(); try await settle(fixture.model)
        expect(fixture.model.phase == .failed && fixture.gate.isLocked && fixture.gate.recoveryError != nil, "Failed rollback locks saved data for recovery")
        expect(await fixture.disk.exists(fixture.transaction.journalURL), "Uncommitted journal remains durable after failed rollback")
        let restart = BackupRestoreTransaction(defaults: fixture.defaults, domain: fixture.suite, disk: fixture.disk)
        try restart.recoverBeforeLoading()
        expect(try TaskPersistence(defaults: fixture.defaults).load().days["2027-01-01"] == nil, "Startup recovery rolls back the entire interrupted import")
        fixture.gate.isLocked = false; fixture.gate.recoveryError = nil
        expect(fixture.model.recoveryURL != nil, "Recovery file survives a failed transaction")

        let timerFixture = try ImportFixture()
        defer { do { try timerFixture.clean() } catch { preconditionFailure("Timer fixture cleanup failed: \(error)") } }
        let checkpoint = ContinuousClock.now, date = Date.now
        timerFixture.workspace.startBothTimers(at: checkpoint, date: date)
        var currentInstant = checkpoint + .seconds(30)
        var currentDate = date.addingTimeInterval(30)
        let model = ImportCoordinator(capture: timerFixture.capture, gate: timerFixture.gate, transaction: timerFixture.transaction,
            now: { currentDate }, instant: { currentInstant })
        var incoming = try KeepDataPayload(timerFixture.capture.capture(.backup, at: currentInstant, date: currentDate))
        incoming.tasks.days["2027-01-01"] = [FocusTask(title: "While timers run")]
        let url = timerFixture.root.appendingPathComponent("timers.keepdata")
        try await timerFixture.disk.write(try await timerFixture.disk.encode(KeepDataEnvelope(incoming, date: date, appVersion: "checks")), to: url)
        model.open(url); try await settle(model)
        expect(timerFixture.workspace.bothTimersRunning(at: currentInstant), "Preview and capture leave both timers running")
        currentInstant += .seconds(30); currentDate = currentDate.addingTimeInterval(30)
        model.apply(); try await settle(model)
        expect(model.phase == .reviewing && !timerFixture.workspace.isRecording(at: currentInstant), "Applying stops timers and requires fresh review for newly elapsed time")
        expect(abs(timerFixture.workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } - 60) < 0.001, "Concurrent timers settle once under Flow priority")
        expect(timerFixture.workspace.ledger.sessions.allSatisfy { $0.source == .flow }, "Concurrent Pomodoro adds no duplicate recording")
        // Retain the live local version when the source has an older checkpoint of its ID.
        if let review = model.review {
            for issue in review.issues where !issue.requiresChoice { model.resolve(issue.id, .local); try await settle(model) }
        }
        model.apply(); try await settle(model)
        expect(model.phase == .success && timerFixture.tasks.archive.days["2027-01-01"] != nil, "Reconfirmed import succeeds after timer checkpoint review")
        expect(!timerFixture.workspace.isRecording(at: currentInstant), "Import never restarts timers")
        expect(timerFixture.workspace.readIndex.taskTimes.seconds.isEmpty, "Derived task index is rebuilt from the committed session snapshot")
    }
    static func habitInstallationChecks() async throws {
        let fixture = try ImportFixture()
        defer { do { try fixture.clean() } catch { preconditionFailure("Habit fixture cleanup failed: \(error)") } }
        let habit = Habit(id: UUID(), name: "Imported timed habit", icon: .book, startDay: "2026-10-01", endDay: nil, goal: .amount(target: 1, unit: .minutes))
        var ledger = TimesheetLedger()
        ledger.record(project: .habits, from: date("2026-10-01"), seconds: 60, calendar: calendar, sessionID: UUID(), task: habit.name, taskReference: .habit(id: habit.id))
        ledger.rememberTask(habit.name, project: .habits, date: date("2026-10-01"), reference: .habit(id: habit.id))
        let archive = HabitArchive(habits: [habit], logs: [.init(habitID: habit.id, dayID: "2026-10-01", amount: 1)])
        let source = payload(ledger, habits: archive)
        var cues = 0; fixture.workspace.onTimerReminder = { _ in cues += 1 }
        try await fixture.open(source)
        fixture.model.apply(); try await settle(fixture.model)
        expect(fixture.model.phase == .success, "Habit history commits successfully across owners")
        expect(fixture.habits.amount(for: habit, on: "2026-10-01") == 2, "Manual minutes and recorded habit time each contribute once after installation")
        expect(fixture.habits.archive.consumedTimerGoals?[habit.id]?.contains("2026-10-01") == true, "Historical timed completions are durably marked consumed")
        expect(fixture.tasks.tasks(on: "2026-10-01").first(where: { $0.habitID == habit.id })?.isComplete == true, "Projected habit tasks refresh from imported time")
        expect(fixture.workspace.taskSuggestions.first?.taskReference == .habit(id: habit.id), "Imported suggestions keep their habit reference")
        fixture.workspace.synchronize()
        expect(cues == 0, "Historical installation and the following tick never replay completion cues")
        expect(try HabitPersistence(defaults: fixture.defaults).load() == fixture.habits.archive, "Silent progress markers survive reload")
    }
}
