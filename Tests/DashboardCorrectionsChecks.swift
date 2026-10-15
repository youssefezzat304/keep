import AppKit
import SwiftUI

@main enum DashboardCorrectionsChecks {
    static var checks = 0, renders = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
    static func main() {
        let app = NSApplication.shared, runner = CorrectionsRunner()
        app.delegate = runner; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(runner) {}
    }
    static func run() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt; calendar.firstWeekday = 2
        let day = "2026-10-15"
        guard let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 16)),
              let defaults = UserDefaults(suiteName: "keep.dashboard-corrections.\(UUID().uuidString)") else { throw CocoaError(.coderInvalidValue) }
        let clock = ContinuousClock.now, project = FocusProject.defaults[0]
        func date(_ hour: Int, _ minute: Int = 0, day: Int = 15) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
        }
        let persistence = TimesheetPersistence(defaults: defaults)
        defer { defaults.removeObject(forKey: persistence.key) }
        var ledger = TimesheetLedger()
        ledger.record(project: project, from: date(0, day: 14), seconds: 19 * 3600, calendar: calendar, sessionID: UUID(), task: "Accidental long timer")
        ledger.record(project: .defaults[1], from: date(10), seconds: 3600, calendar: calendar, sessionID: UUID(), task: "German")
        ledger.record(project: project, from: date(9, day: 16), seconds: 3600, calendar: calendar, sessionID: UUID())
        try persistence.save(ledger)
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, date: now)
        defer { workspace.shutdown() }
        let cache = StatsCache(), supplement = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
        var cursor: (epoch: UUID, revision: UInt64)?
        func check(_ expected: Double, at instant: ContinuousClock.Instant = clock, date: Date = now) async throws {
            let projectSeconds = workspace.weeklyProjectSeconds(projectID: project.id, today: date)
            let week = TimesheetWeek(containing: date, calendar: calendar)
            let days = week.days.filter { $0.date <= date }.map(\.id)
            expect(near(projectSeconds, expected), "Project goal follows corrected Timesheet totals")
            expect(near(projectSeconds, workspace.ledger.entries.filter { $0.project.id == project.id && days.contains($0.dayID) }.reduce(0) { $0 + $1.seconds }), "Goal and visible Timesheet share the same current-week time")
            let batch = workspace.readIndex.batch(since: cursor?.revision, epoch: cursor?.epoch)
            var query = StatsQuery(); query.anchor = calendar.date(byAdding: .weekOfYear, value: -2, to: date); query.projectID = "missing"
            let stats = try await cache.snapshot(batch: batch, query: query, supplement: supplement, now: date, calendar: calendar)
            expect(near(stats.weeklyGoalSeconds, expected + 3600), "Cached weekly goal follows all projects' corrected totals independently of date/project filters")
            cursor = (batch.epoch, batch.revision)
        }
        try await check(19 * 3600)
        workspace.edit(seconds: 10 * 3600 + 22 * 60, project: project, dayID: "2026-10-14", at: clock, date: now)
        try await check(37320)
        expect(workspace.ledger.sessions.first?.seconds == 19 * 3600, "A total correction never silently rewrites recorded Calendar history")
        workspace.selectProject(project, at: clock, date: now); workspace.play(.flow, at: clock, date: now)
        workspace.synchronize(at: clock + .seconds(60), date: now.addingTimeInterval(60))
        try await check(37380, at: clock + .seconds(60), date: now.addingTimeInterval(60))
        workspace.edit(seconds: 0, project: project, dayID: day, at: clock + .seconds(60), date: now.addingTimeInterval(60))
        try await check(37320, at: clock + .seconds(60), date: now.addingTimeInterval(60))
        workspace.stopBothTimers(at: clock + .seconds(90), date: now.addingTimeInterval(90))
        try await check(37350, at: clock + .seconds(90), date: now.addingTimeInterval(90))
        if let accidental = workspace.ledger.sessions.first(where: { $0.task == "Accidental long timer" }) {
            try workspace.editSession(id: accidental.id, start: accidental.start, end: accidental.end.addingTimeInterval(-60), at: clock + .seconds(90), date: now.addingTimeInterval(90))
            try await check(37290)
            workspace.removeTimesheetProject(project, dayIDs: ["2026-10-14", day], at: clock + .seconds(90), date: now.addingTimeInterval(90))
            try await check(0)
            workspace.undoTimesheetRemoval(at: clock + .seconds(90), date: now.addingTimeInterval(90))
            try await check(37290)
        }
        let reloaded = WorkspaceModel(persistence: persistence, calendar: calendar, date: now)
        defer { reloaded.shutdown() }
        expect(near(reloaded.weeklyProjectSeconds(projectID: project.id, today: now), 37290), "Corrected goals survive reload and exclude future time")
        try workspace.updateProjectTargets(projectID: project.id, targets: .init(goal: 1200, minimum: 1020), at: clock + .seconds(90), date: now.addingTimeInterval(90))
        let snapshot = PersistentSnapshot(workspace: workspace.ledger, tasks: TaskArchive(), habits: HabitArchive(), settings: PortableSettings(SettingsArchive()), projects: workspace.readIndex.statsProjects, capturedAt: now, calendar: calendar)
        let reports = try ExportReports.make(.init(data: .stats, from: now, through: now, projectID: "missing", taskKeys: nil), snapshot: snapshot)
        let targetCSV = reports.first { $0.filename == "weekly_targets.csv" }.map { String(decoding: $0.contents, as: UTF8.self) } ?? ""
        expect(targetCSV.contains("37290.0"), "Project goal exports use the same corrected progress")

        func session(_ id: String, _ project: FocusProject, _ start: Int, _ end: Int, title: String = "Work") -> RecordedSession {
            let midnight = calendar.startOfDay(for: now)
            return .init(id: id, recordingID: UUID(), dayID: day, project: project, task: title, source: .flow, timeZoneID: calendar.timeZone.identifier,
                         start: midnight.addingTimeInterval(Double(start * 60)), end: midnight.addingTimeInterval(Double(end * 60)))
        }
        let a = session("a", project, 600, 620), b = session("b", project, 630, 660, title: "Review")
        let grouped = CalendarProjectBlock.grouping([b, a])
        expect(grouped.count == 1 && grouped[0].sessions.map(\.id) == ["a", "b"], "Consecutive same-project sessions share one block in chronological order")
        expect(grouped[0].gaps == [620..<630] && grouped[0].seconds == 3000, "Only the actual ten-minute gap is shaded; it never counts as focus")
        expect(grouped[0].titles == ["Work", "Review"], "Grouping preserves different task titles")
        let touching = CalendarProjectBlock.grouping([a, session("touching", project, 620, 640)])
        expect(touching[0].gaps.isEmpty, "Touching entries form a continuous block")
        let overlapping = CalendarProjectBlock.grouping([a, session("overlap", project, 610, 640), session("contained", project, 612, 615)])
        expect(overlapping.count == 1 && overlapping[0].gaps.isEmpty && overlapping[0].endMinute == 640, "Overlapping and contained entries do not invent gaps")
        let intervening = CalendarProjectBlock.grouping([a, session("other", .defaults[1], 620, 630), b])
        expect(intervening.count == 3, "Another project interrupts a run instead of being shaded as a gap")
        let sameName = FocusProject(id: "different-id", name: project.name, accent: project.accent, category: project.category)
        expect(CalendarProjectBlock.grouping([a, session("different", sameName, 625, 640)]).count == 2, "Project identity, not name/color, controls grouping")
        expect(CalendarProjectBlock.placements(grouped, hourHeight: 48).map(\.lane) == [0], "Short same-project entries no longer split into parallel lanes")
        let separate = CalendarProjectBlock.grouping([session("short", project, 600, 605), session("different", .defaults[1], 606, 611)])
        expect(CalendarProjectBlock.placements(separate, hourHeight: 72).map(\.lane) == [0, 1], "Different-project entries retain the existing minimum-height lane layout")
        let actualOverlap = CalendarProjectBlock.grouping([a, session("other-project", .defaults[1], 610, 650)])
        expect(CalendarProjectBlock.placements(actualOverlap, hourHeight: 108).map(\.lane) == [0, 1], "Different overlapping projects stay side by side")
        expect(CalendarProjectBlock.placements(actualOverlap, hourHeight: 108).allSatisfy { $0.laneCount == 2 }, "Only overlapping blocks share a column")
        let isolated = CalendarProjectBlock.grouping([a, session("later", .defaults[1], 800, 840)])
        expect(CalendarProjectBlock.placements(isolated, hourHeight: 72).allSatisfy { $0.lane == 0 && $0.laneCount == 1 }, "Unrelated later overlaps cannot leave isolated blocks at half width")
        print("Passed \(checks) corrected goal and calendar grouping checks")

        var visualLedger = TimesheetLedger()
        let visualDate = Date.now, visualStart = calendar.startOfDay(for: visualDate)
        for (start, minutes, project, title) in [
            (9 * 60, 20, FocusProject.defaults[0], "Work"), (9 * 60 + 30, 30, .defaults[0], "Review notes"),
            (11 * 60, 45, .defaults[1], "Listening"), (11 * 60 + 55, 35, .defaults[1], "Reading"),
            (13 * 60, 8, .defaults[0], "Short entry"), (13 * 60 + 10, 15, .defaults[1], "Different project"),
            (14 * 60, 30, .defaults[0], "Work")
        ] {
            visualLedger.record(project: project, from: visualStart.addingTimeInterval(Double(start * 60)), seconds: Double(minutes * 60), calendar: calendar, sessionID: UUID(), task: title)
        }
        let visual = WorkspaceModel(ledger: visualLedger, calendar: calendar, date: visualDate)
        defer { visual.shutdown() }
        let output = URL(fileURLWithPath: "/tmp/keep-dashboard-corrections-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                for page in DashboardPage.allCases {
                    let root = DashboardView(workspace: visual, initialPage: page).padding(24).background(KeepTheme.paper).keepAppearance(appearance)
                    try await render(root, size: size, to: output.appendingPathComponent("\(page.rawValue)-\(label)-\(appearance.rawValue).png"))
                }
            }
            let group = CalendarProjectBlock.grouping(visual.ledger.sessions)[0]
            try await render(CalendarBlockEntries(block: group, workspace: visual, onSelect: { _ in }).keepAppearance(appearance), size: NSSize(width: 500, height: 520), to: output.appendingPathComponent("entries-\(appearance.rawValue).png"))
        }
        print("Rendered \(renders) native dashboard and grouped-entry layouts in \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_DASHBOARD_CORRECTIONS_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated dashboard corrections"
            let host = NSHostingView(rootView: DashboardView(workspace: visual, initialPage: .calendar).padding(24).background(KeepTheme.paper).keepAppearance(.light)); host.sizingOptions = []
            window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive dashboard corrections ready.\n".utf8))
            try await Task.sleep(for: .seconds(90)); window.close()
        }
    }

    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root); host.sizingOptions = []
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size); window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(300)); host.layoutSubtreeIfNeeded()
        expect(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1, "Native dashboard retains its requested viewport")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); renders += 1
    }
}

private final class CorrectionsRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await DashboardCorrectionsChecks.run() }
            catch { preconditionFailure("Dashboard corrections failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
