import AppKit
import Foundation

private final class FakePanel: ExportSavePanel {
    var url: URL?
    var calls = 0
    var hold = false
    var continuation: CheckedContinuation<URL?, Never>?
    func destination(filename: String, data: ExportData, window: NSWindow?) async throws -> URL? {
        calls += 1
        if hold { return await withCheckedContinuation { continuation = $0 } }
        return url
    }
    func cancel() { continuation?.resume(returning: nil); continuation = nil }
}
private actor FakeFiles: ExportFileWriting {
    var prepared = 0, saved = 0, removed = 0
    var failSave = false
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    func configure(hold: Bool = false, failSave: Bool = false) { self.hold = hold; self.failSave = failSave }
    func release() { continuation?.resume(); continuation = nil }
    func counts() -> [Int] { [prepared, saved, removed] }
    func prepare(_ request: ExportRequest, snapshot: PersistentSnapshot) async throws -> ExportArtifact {
        prepared += 1
        if hold { await withCheckedContinuation { continuation = $0 } }
        return .init(root: URL(fileURLWithPath: "/fake-stage"), url: URL(fileURLWithPath: "/fake-stage/report.csv"), filename: request.filename(calendar: snapshot.calendar))
    }
    func save(_ artifact: ExportArtifact, to destination: URL) throws { if failSave { throw CocoaError(.fileWriteNoPermission) }; saved += 1 }
    func remove(_ artifact: ExportArtifact) { removed += 1 }
}

@main enum ExportChecks {
    static var count = 0
    static func expect(_ value: Bool, _ message: String) { count += 1; precondition(value, message) }
    static func rejects(_ message: String, _ action: () throws -> Void) {
        do { try action(); preconditionFailure(message) } catch { count += 1 }
    }
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Export did not settle")
    }
    /// Small RFC4180 reader so checks assert decoded fields, including quoted multiline text.
    static func csv(_ data: Data) -> [[String]] {
        let chars = Array(String(decoding: data, as: UTF8.self))
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append(c); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\r" || c == "\n" || c == "\r\n") && !quoted {
                row.append(field); rows.append(row); field = ""; row = []
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else { field.append(c) }
            i += 1
        }
        return rows
    }
    static func main() async throws {
        _ = NSApplication.shared
        var calendar = StatsSnapshot.calendar(.current)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.locale = Locale(identifier: "de_DE")
        func date(_ day: Int, _ month: Int = 10, _ year: Int = 2026, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
        }
        let now = date(8), instant = ContinuousClock.now
        let project = FocusProject(id: "custom", name: "=SUM(1,2)", accent: .sage, category: "Test")
        let deleted = FocusProject(id: "deleted", name: "Old project", accent: .butter, category: "Test")
        var ledger = TimesheetLedger()
        ledger.registerProject(project); ledger.registerProject(deleted)
        ledger.record(project: project, from: date(7), seconds: 3600, calendar: calendar, sessionID: UUID(), task: "Hören, \"日本語\"\nNotes", source: .flow)
        ledger.record(project: project, from: date(6), seconds: 1800, calendar: calendar, sessionID: UUID(), task: " horen ")
        ledger.record(project: deleted, from: date(6), seconds: 600, calendar: calendar, sessionID: UUID())
        ledger.record(project: .unassigned, from: date(31, 12, 2025, 23), seconds: 7200, calendar: calendar, sessionID: UUID())
        ledger.setSeconds(0, project: project, dayID: "2026-10-05")
        ledger.setSeconds(5000, project: project, dayID: "2026-10-07")
        ledger.setProjectTargets(.init(goal: 600, minimum: 120), projectID: project.id)
        ledger.deleteProject(id: deleted.id)
        ledger.beginPomodoroHistory(at: date(6))
        ledger.recordCompletion(.init(id: UUID(), project: project, task: "horen", completedAt: date(6).addingTimeInterval(1800), dayID: "2026-10-06", timeZoneID: calendar.timeZone.identifier, focusDuration: 1500))
        let workspace = WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
        let habit = Habit(id: UUID(), name: "@Read", icon: .book, startDay: "2026-10-01", endDay: nil,
            goal: .amount(target: 10, unit: .minutes), weekdays: [.monday, .wednesday, .friday], weeklyTargets: .init(goal: 120, minimum: 30))
        let habits = HabitStore(archive: .init(habits: [habit], logs: [.init(habitID: habit.id, dayID: "2026-10-05", amount: 10), .init(habitID: habit.id, dayID: "2026-10-07", amount: 5)]), calendar: calendar)
        let tasks = DailyTaskStore(archive: .init(days: ["2026-10-05": [FocusTask(title: "Task", isComplete: true), FocusTask(title: "Another")]]), calendar: calendar, habits: habits)
        let preferences = AppPreferences(); preferences.weeklyFocusGoalMinutes = 60
        let gate = BackupRestoreGate()
        let capture = SnapshotCapture(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, gate: gate)
        let snapshot = try capture.capture(.stats, at: instant, date: now)
        let encoded = try CSVReport.encode(headers: ["text", "number"], rows: [[.text("Hello, \"世界\"\nline"), .number(-12.5)], [.text(" \t=1+1"), .integer(2)], [.text("@formula"), .value("")], [.text("\ntext"), .integer(0)]])
        let decoded = csv(encoded)
        expect(decoded[1] == ["Hello, \"世界\"\nline", "-12.5"], "Quoting, Unicode, multiline and numeric minus")
        expect(decoded[2][0] == "' \t=1+1" && decoded[3][0] == "'@formula" && decoded[4][0] == "'\ntext", "Spreadsheet formula protection")
        expect(try CSVReport.encode(headers: ["a", "b"], rows: []) == Data("a,b\r\n".utf8), "Header-only empty data")
        func request(_ data: ExportData, from: Date? = nil, through: Date? = nil, projectID: String? = nil, keys: Set<String>? = nil) -> ExportRequest {
            .init(data: data, from: from ?? date(5), through: through ?? now, projectID: projectID, taskKeys: keys)
        }
        func rows(_ reports: [ExportReport], _ filename: String) -> [[String]] {
            csv(reports.first { $0.filename == filename }?.contents ?? Data())
        }
        let calendarReports = try ExportReports.make(request(.calendar), snapshot: snapshot)
        let sessions = csv(calendarReports[0].contents)
        expect(sessions.count == 4 && sessions[1][2] == "2026-10-06" && sessions[3][2] == "2026-10-07", "Stable civil-day ordering")
        expect(sessions[3][4] == "'=SUM(1,2)" && sessions[3][6] == "Hören, \"日本語\"\nNotes", "User text safely preserved")
        expect(sessions[1][8].hasSuffix("+02:00"), "Recorded timezone offset, locale-independent timestamps")
        expect(sessions.contains { $0.count > 5 && $0[3] == "deleted" && $0[5] == "true" }, "Deleted historical project included")
        let selected = try ExportReports.make(request(.calendar, projectID: project.id, keys: ["horen"]), snapshot: snapshot)
        expect(csv(selected[0].contents).count == 2, "Case/diacritic normalized task filtering")
        let sheet = csv(try ExportReports.make(request(.timesheet, projectID: project.id), snapshot: snapshot)[0].contents)
        expect(sheet[1].suffix(2) == ["0.0", "0.0"] && sheet.last?.suffix(2) == ["5000.0", "3600.0"], "Saved zero rows and adjusted/recorded separation")
        let weekDays = try ExportReports.dayIDs(from: date(5), through: now, calendar: calendar)
        let projection = WeeklyProjection(days: weekDays, index: workspace.readIndex)
        expect(sheet.dropFirst().reduce(0) { $0 + (Double($1[4]) ?? 0) } == projection.rowTotals[project.id], "Timesheet projection reconciliation")
        let reports = try ExportReports.make(request(.stats), snapshot: snapshot)
        expect(reports.count == 11 && Set(reports.map(\.filename)).count == 11, "Full Stats CSV bundle")
        expect(try ExportReports.make(request(.stats), snapshot: snapshot).map(\.contents) == reports.map(\.contents), "Deterministic report bytes")
        let summary = rows(reports, "summary.csv")
        expect(summary[1][0] == "6000.0" && summary[1][7] == "1" && summary[1][9] == "partial", "Focus and partial Pomodoro coverage")
        let daily = rows(reports, "focus_daily.csv")
        expect(daily.count == 5 && daily[1] == ["2026-10-05", "0.0"], "Complete inclusive daily range including zero days")
        let filteredStats = try ExportReports.make(request(.stats, projectID: project.id, keys: ["horen"]), snapshot: snapshot)
        expect(rows(filteredStats, "summary.csv")[1][0] == "1800.0", "Stats filtered values reconcile")
        expect(rows(filteredStats, "tasks.csv") == rows(reports, "tasks.csv") && rows(filteredStats, "habits.csv") == rows(reports, "habits.csv"), "Date-only task and habit scopes ignore filters")
        expect(rows(filteredStats, "adjusted_totals.csv").last?.suffix(2) == ["5000.0", "3600.0"], "Adjusted totals ignore task filters")
        expect(rows(reports, "habits.csv")[1][2...4] == ["2", "1", "0.5"], "Scheduled habit opportunities and partial progress")
        let targets = rows(reports, "weekly_targets.csv")
        expect(targets.count == 4 && targets[1][3] == "2026-10-05" && targets.last?[7] == "15.0", "Current-week targets, units and saved habit progress")
        let cross = try ExportReports.make(request(.stats, from: date(31, 12, 2025), through: date(2, 1)), snapshot: snapshot)
        expect(rows(cross, "focus_daily.csv").dropFirst().map { $0[1] } == ["3600.0", "3600.0", "0.0"], "Cross-year daily data extends beyond activity-grid year")
        expect(rows(cross, "summary.csv")[1][7] == "" && rows(cross, "summary.csv")[1][9] == "unavailable", "Legacy unavailable Pomodoros remain blank")
        expect(rows(cross, "weekly_targets.csv") == targets, "Weekly targets do not inherit historical export range")
        let empty = try ExportReports.make(request(.calendar, projectID: "missing"), snapshot: snapshot)
        expect(csv(empty[0].contents).count == 1, "Empty export retains header")
        rejects("Invalid reversed range") { try request(.stats, from: now, through: date(5)).validate(now: now, calendar: calendar) }
        rejects("Future date") { try request(.stats, through: date(9)).validate(now: now, calendar: calendar) }
        rejects("Unscoped task keys") { try request(.stats, keys: ["horen"]).validate(now: now, calendar: calendar) }
        gate.isLocked = true
        rejects("Restore gate blocks capture") { _ = try capture.capture(.workspace, date: now) }
        gate.isLocked = false
        let suite = "keep.export.checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw ExportFailure.unavailable }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: "keep.tasks.v1")
        let brokenTasks = DailyTaskStore(persistence: TaskPersistence(defaults: defaults), calendar: calendar)
        let protected = SnapshotCapture(workspace: workspace, tasks: brokenTasks, habits: habits, preferences: preferences, gate: gate)
        rejects("Protected Stats data cannot appear empty") { _ = try protected.capture(.stats, date: now) }
        expect(try protected.capture(.workspace, date: now).tasks == nil, "Calendar does not require task store")
        expect(defaults.data(forKey: "keep.tasks.v1") == Data("broken".utf8), "Failed loads preserve original bytes")
        defaults.set(Data("broken".utf8), forKey: "keep.habits.v1")
        defaults.set(Data("broken".utf8), forKey: "keep.preferences.v1")
        defaults.set(Data("broken".utf8), forKey: "keep.timesheet.v1")
        let brokenHabits = HabitStore(persistence: HabitPersistence(defaults: defaults))
        let brokenPreferences = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
        let brokenWorkspace = WorkspaceModel(persistence: TimesheetPersistence(defaults: defaults))
        rejects("Protected habits block Stats") { _ = try SnapshotCapture(workspace: workspace, tasks: tasks, habits: brokenHabits, preferences: preferences).capture(.stats, date: now) }
        rejects("Protected settings block Stats") { _ = try SnapshotCapture(workspace: workspace, tasks: tasks, habits: habits, preferences: brokenPreferences).capture(.stats, date: now) }
        rejects("Protected workspace blocks every export") { _ = try SnapshotCapture(workspace: brokenWorkspace, tasks: tasks, habits: habits, preferences: preferences).capture(.workspace, date: now) }
        expect(["keep.habits.v1", "keep.preferences.v1", "keep.timesheet.v1"].allSatisfy { defaults.data(forKey: $0) == Data("broken".utf8) }, "Every protected archive preserves original bytes")
        let continuing = WorkspaceModel(calendar: calendar, focusDuration: 1000, date: now)
        continuing.play(.pomodoro, at: instant, date: now); continuing.play(.flow, at: instant, date: now)
        _ = try SnapshotCapture(workspace: continuing, tasks: tasks, habits: habits, preferences: preferences).capture(.stats, at: instant.advanced(by: .seconds(5)), date: now.addingTimeInterval(5))
        expect(continuing.pomodoro.phase(at: instant.advanced(by: .seconds(5))) == .running && continuing.flow.phase(at: instant.advanced(by: .seconds(5))) == .running, "Both timers remain running during ordinary capture")
        let live = WorkspaceModel(calendar: calendar, focusDuration: 10, date: now)
        live.play(.pomodoro, at: instant, date: now); live.play(.flow, at: instant, date: now)
        let liveCapture = SnapshotCapture(workspace: live, tasks: tasks, habits: habits, preferences: preferences, gate: gate)
        let frozen = try liveCapture.capture(.stats, at: instant.advanced(by: .seconds(15)), date: now.addingTimeInterval(15))
        expect(frozen.workspace.sessions.reduce(0) { $0 + $1.seconds } == 15 && frozen.workspace.completedPomodoros.count == 1, "Concurrent capture settles recorder and completion once, with Flow priority")
        expect(live.flow.phase(at: instant.advanced(by: .seconds(15))) == .running, "Flow continues through capture")
        live.synchronize(at: instant.advanced(by: .seconds(20)), date: now.addingTimeInterval(20))
        expect(frozen.workspace.sessions.reduce(0) { $0 + $1.seconds } == 15 && live.ledger.sessions.reduce(0) { $0 + $1.seconds } == 20, "Snapshot immune to later mutations without duplicated time")
        expect(live.ledger.completedPomodoros.count == 1, "Completion not duplicated by export")
        try await timeZones(calendar: calendar, now: now)
        try await fileChecks(request: request(.stats), snapshot: snapshot, reports: reports)
        try await modelChecks(capture: capture, now: now, instant: instant)
        print("Export checks passed: \(count)")
    }

    static func timeZones(calendar: Calendar, now: Date) async throws {
        var ledger = TimesheetLedger()
        let project = FocusProject.defaults[0]
        let fall = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 1)) ?? now
        ledger.record(project: project, from: fall, seconds: 4 * 3600, calendar: calendar, sessionID: UUID(), source: .flow)
        var west = calendar; west.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        ledger.record(project: project, from: fall, seconds: 60, calendar: west, sessionID: UUID())
        let workspace = WorkspaceModel(ledger: ledger, calendar: calendar, date: fall.addingTimeInterval(86400))
        let capture = SnapshotCapture(workspace: workspace, tasks: DailyTaskStore(), habits: HabitStore(), preferences: AppPreferences())
        let snapshot = try capture.capture(.stats, date: fall.addingTimeInterval(86400))
        let request = ExportRequest(data: .calendar, from: fall.addingTimeInterval(-86400), through: fall, projectID: nil, taskKeys: nil)
        let rows = csv(try ExportReports.make(request, snapshot: snapshot)[0].contents)
        expect(rows.count == 3 && rows[2][8].hasSuffix("+02:00") && rows[2][9].hasSuffix("+01:00"), "DST uses each endpoint's recorded offset")
        expect(rows[1][2] == "2026-10-24" && rows[1][10] == west.timeZone.identifier, "Recorded civil day preserved across timezone change")
        let stats = try ExportReports.make(.init(data: .stats, from: request.from, through: request.through, projectID: nil, taskKeys: nil), snapshot: snapshot)
        let hourly = csv(stats.first { $0.filename == "focus_hours.csv" }?.contents ?? Data())
        expect(Double(hourly[3][1]) == 7200, "Repeated recorded local hour counted twice")
        // Spring forward has no local 02:00 hour.
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 1)) ?? now
        var springLedger = TimesheetLedger()
        springLedger.record(project: project, from: spring, seconds: 3 * 3600, calendar: calendar, sessionID: UUID())
        let springWorkspace = WorkspaceModel(ledger: springLedger, calendar: calendar, date: now)
        let springSnapshot = try SnapshotCapture(workspace: springWorkspace, tasks: DailyTaskStore(), habits: HabitStore(), preferences: AppPreferences()).capture(.stats, date: now)
        let input = ExportReports.statsInput(.init(data: .stats, from: spring, through: spring, projectID: nil, taskKeys: nil), snapshot: springSnapshot, tasks: TaskArchive(), habits: HabitArchive())
        expect(try StatsSnapshot.make(input).hours[2] == 0, "Missing DST hour stays zero")
    }

    static func fileChecks(request: ExportRequest, snapshot: PersistentSnapshot, reports: [ExportReport]) async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("keep-export-tests-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let files = ExportFiles(temporaryRoot: root)
        let artifact = try await files.prepare(request, snapshot: snapshot)
        expect(try Data(contentsOf: artifact.url).prefix(2) == Data([0x50, 0x4b]), "Foundation produces a ZIP")
        let extracted = root.appendingPathComponent("extracted")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", artifact.url.path, extracted.path]
        try process.run(); process.waitUntilExit()
        expect(process.terminationStatus == 0, "ZIP can be extracted by native tooling")
        let enumerator = manager.enumerator(at: extracted, includingPropertiesForKeys: [.isRegularFileKey])
        var actual: [String: Data] = [:]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { actual[url.lastPathComponent] = try Data(contentsOf: url) }
        }
        expect(actual == Dictionary(uniqueKeysWithValues: reports.map { ($0.filename, $0.contents) }), "ZIP contains exactly the generated reports")
        let destination = root.appendingPathComponent("saved.zip")
        try Data("old".utf8).write(to: destination)
        try await files.save(artifact, to: destination)
        expect(try Data(contentsOf: destination) == Data(contentsOf: artifact.url), "Atomic overwrite saves complete artifact")
        let bad = ExportArtifact(root: artifact.root, url: root.appendingPathComponent("missing"), filename: "missing")
        do { try await files.save(bad, to: destination); preconditionFailure("Missing staged file") } catch { count += 1 }
        expect(try Data(contentsOf: destination) == Data(contentsOf: artifact.url), "Failed overwrite preserves existing destination")
        do {
            _ = try await files.prepare(.init(data: .stats, from: request.through, through: request.from, projectID: nil, taskKeys: nil), snapshot: snapshot)
            preconditionFailure("Invalid request must not prepare")
        } catch { count += 1 }
        expect(try manager.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("Keep-Export-") }.count == 1, "Failed preparation removes its temporary directory")
        try await files.remove(artifact)
        expect(!manager.fileExists(atPath: artifact.root.path), "Staging removed after save")
        let cancelled = Task { try await files.prepare(request, snapshot: snapshot) }; cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled preparation") } catch { count += 1 }
        expect(try manager.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix("Keep-Export-") }, "Cancelled preparation cleans staging")
    }

    static func modelChecks(capture: SnapshotCapture, now: Date, instant: ContinuousClock.Instant) async throws {
        let panel = FakePanel(), files = FakeFiles()
        let model = ExportModel(capture: capture, files: files, panel: panel, now: { now }, instant: { instant })
        expect(model.data == .calendar && model.projectID == nil && model.taskKeys == nil && TaskDay.id(for: model.from, calendar: model.calendar) == "2026-10-05", "Window defaults independent from tabs")
        model.start(); model.start()
        try await waitUntil { !model.status.busy }
        expect(await files.counts() == [1, 0, 1] && model.status == .idle, "Duplicate prevented; native panel cancel neutral and cleaned")
        panel.url = URL(fileURLWithPath: "/fake-destination")
        await files.configure(failSave: true); model.start()
        try await waitUntil { !model.status.busy }
        if case .error = model.status { count += 1 } else { preconditionFailure("Save failure must surface") }
        expect(await files.counts() == [2, 0, 2], "Save failure cleans staging")
        await files.configure(hold: true)
        model.start(); try await Task.sleep(for: .milliseconds(20)); model.cancel(); await files.release()
        try await waitUntil { !model.status.busy }
        expect(await files.counts() == [3, 0, 3], "Cancelled preparation cannot open panel and cleans returned staging")
        await files.configure(hold: true)
        model.start(); try await Task.sleep(for: .milliseconds(20)); capture.gate?.generation = UUID(); await files.release()
        try await waitUntil { !model.status.busy }
        expect(await files.counts() == [4, 0, 4], "Restore generation fences stale preparation")
        await files.configure(); panel.hold = true
        model.start(); try await waitUntil { model.status == .readyToSave }
        model.cancel(); try await waitUntil { !model.status.busy }
        expect(await files.counts() == [5, 0, 5], "Save sheet cancellation releases staging")
        panel.hold = false
        let other = ExportModel(capture: capture, files: FakeFiles(), panel: FakePanel(), now: { now })
        other.data = .stats; other.from = now
        expect(model.data == .calendar && model.from != other.from, "Independent window selections")
        model.start(); try await waitUntil { !model.status.busy }
        let finalCounts = await files.counts()
        expect(model.status == .success("fake-destination") && finalCounts == [6, 1, 6], "Local save completion and cleanup")
    }
}
