import AppKit
import SwiftUI

@main enum StatsGraphChecks {
    static var checks = 0, renders = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }
    static func main() {
        let app = NSApplication.shared, runner = StatsGraphRunner()
        app.delegate = runner; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(runner) {}
    }
    static func run() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt; calendar.locale = Locale(identifier: "en_GB")
        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
        }
        let now = date(13, 16, 30), clock = ContinuousClock.now
        let duplicate = FocusProject(id: "same-name", name: "Keep", accent: .denim, category: "Personal project")
        var ledger = TimesheetLedger(); ledger.registerProject(duplicate)
        for (day, hour, minutes, project) in [
            (7, 9, 30, FocusProject.defaults[0]),
            (12, 9, 120, .defaults[0]), (12, 13, 180, .defaults[1]),
            (13, 9, 60, .defaults[0]), (13, 10, 60, .defaults[1]),
            (13, 11, 30, .unassigned), (13, 12, 30, duplicate),
            (13, 16, 60, .defaults[1]), (14, 9, 60, .defaults[0])
        ] {
            ledger.record(project: project, from: date(day, hour), seconds: Double(minutes * 60), calendar: calendar, sessionID: UUID(), task: "Work")
        }
        let workspace = WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
        defer { workspace.shutdown() }
        let empty = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
        let cache = StatsCache()
        var cursor: (epoch: UUID, revision: UInt64)?
        func snapshot(_ query: StatsQuery = StatsQuery(), at current: Date = now) async throws -> StatsSnapshot {
            let batch = workspace.readIndex.batch(since: cursor?.revision, epoch: cursor?.epoch)
            let value = try await cache.snapshot(batch: batch, query: query, supplement: empty, now: current, calendar: calendar)
            let input = StatsInput(query: query, now: current, calendar: calendar, projects: workspace.readIndex.statsProjects,
                sessions: workspace.ledger.sessions.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, start: $0.start, end: $0.end, timeZoneID: $0.timeZoneID) },
                completions: [], historyStartedAt: nil, entries: [], tasks: [], habits: [])
            let direct = try StatsSnapshot.make(input)
            expect(value.todayID == direct.todayID && zip(value.todayHours, direct.todayHours).allSatisfy(close), "Cached today's hours match direct aggregation")
            expect(zip(value.buckets, direct.buckets).allSatisfy {
                $0.id == $1.id && $0.projects.map(\.id) == $1.projects.map(\.id)
                    && zip($0.projects, $1.projects).allSatisfy { close($0.seconds, $1.seconds) && $0.name == $1.name && $0.accent == $1.accent }
            }, "Cached project stacks match direct aggregation")
            expect(value.buckets.allSatisfy { close($0.seconds, $0.projects.reduce(0) { $0 + $1.seconds }) }, "Stack segments reconcile with each period total")
            cursor = (batch.epoch, batch.revision)
            return value
        }
        let current = try await snapshot()
        expect(close(current.todayHours.reduce(0, +), 12600) && close(current.todayHours[16], 1800), "Today excludes yesterday and clips incomplete/future sessions at now")
        expect(current.buckets.first?.projects.count == 2, "A day includes both recorded projects")
        let today = current.buckets.first { $0.id == "2026-10-13" }
        expect(today?.projects.count == 4 && today?.projects.filter { $0.name == "Keep" }.count == 2, "Same-name projects remain separate by identity")
        expect(today?.projects.first { $0.id == FocusProject.unassigned.id }?.accent == "neutral", "Unassigned work uses its project color")
        var past = StatsQuery(); past.anchor = date(7)
        let prior = try await snapshot(past)
        expect(close(prior.total, 1800) && prior.todayHours == current.todayHours, "Past-week browsing retains today's hourly chart")
        var year = past; year.period = .year; year.anchor = calendar.date(byAdding: .year, value: -1, to: now)
        expect(try await snapshot(year).todayHours == current.todayHours, "Browsing another year retains today's hours")
        var filtered = past; filtered.projectID = FocusProject.defaults[1].id
        let german = try await snapshot(filtered)
        expect(close(german.todayHours.reduce(0, +), 5400) && german.total == 0, "Today's chart retains project filters even outside selected dates")
        filtered.taskKeys = ["missing"]
        expect(try await snapshot(filtered).todayHours.allSatisfy { $0 == 0 }, "Today's chart retains task filters and shows a genuine empty result")
        for period in [StatsPeriod.month, .year, .custom] {
            var query = StatsQuery(); query.period = period
            query.customStart = date(1); query.customEnd = calendar.date(byAdding: .day, value: 70, to: now) ?? now
            let value = try await snapshot(query)
            expect(close(value.buckets.reduce(0) { $0 + $1.seconds }, current.total + 1800), "Month/year/long custom groups keep the same project totals")
        }
        if let record = workspace.ledger.sessions.first(where: { $0.dayID == "2026-10-13" && $0.project.id == "keep" }) {
            try workspace.editSession(id: record.id, start: record.start, end: record.end.addingTimeInterval(600), at: clock, date: now)
            let extended = try await snapshot(past)
            expect(close(extended.todayHours[9], 3600) && close(extended.todayHours[10], 4200), "An edit outside the viewed week patches today's hours")
            try workspace.deleteSession(id: record.id, at: clock, date: now)
            expect(try await snapshot().buckets.first { $0.id == "2026-10-13" }?.projects.contains { $0.id == "keep" } == false, "Removing a session removes its stack segment")
        }
        let edited = FocusProject(id: duplicate.id, name: "Reading and notes with a longer project name", accent: .plum, category: duplicate.category)
        try workspace.updateProject(duplicate, name: edited.name, accent: edited.accent, at: clock, date: now)
        expect(try await snapshot().buckets.first { $0.id == "2026-10-13" }?.projects.contains { $0.name == edited.name && $0.accent == "plum" } == true, "Rename and recolor update project stack metadata")
        let nextDay = try await snapshot(past, at: date(14, 10))
        expect(nextDay.todayID == "2026-10-14" && close(nextDay.todayHours.reduce(0, +), 3600), "Midnight advances today's hours while browsing an earlier week")
        expect(try await snapshot(past, at: date(15)).todayHours.allSatisfy { $0 == 0 }, "A day with no sessions displays zero, without falling back to yesterday")
        print("Passed \(checks) stacked project and today-hour checks")

        let output = URL(fileURLWithPath: "/tmp/keep-stats-graph-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                try await render(StatsGraphPanel(snapshot: current).keepAppearance(appearance), size: size, to: output.appendingPathComponent("graphs-\(label)-\(appearance.rawValue).png"))
            }
            try await render(StatsBarChart(title: "Focus by hour", points: current.todayHours.enumerated().map {
                .init(id: $0.offset, label: String(format: "%02d:00", $0.offset), seconds: $0.element)
            }, subtitle: "Today · Tue, 13 Oct 2026").padding(24).background(KeepTheme.surface).keepAppearance(appearance),
                size: NSSize(width: 632, height: 310), to: output.appendingPathComponent("today-\(appearance.rawValue).png"))
            try await render(StatsBarChart(title: "Your focus over time", points: prior.buckets.enumerated().map {
                .init(id: $0.offset, label: $0.element.label, seconds: $0.element.seconds, projects: $0.element.projects)
            }).padding(24).background(KeepTheme.surface).keepAppearance(appearance), size: NSSize(width: 632, height: 310),
                to: output.appendingPathComponent("past-week-\(appearance.rawValue).png"))
        }
        print("Rendered \(renders) native Stats graph layouts in \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_STATS_GRAPH_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated Stats graphs"
            window.contentView = NSHostingView(rootView: StatsGraphPanel(snapshot: current).keepAppearance(.light))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive Stats graphs ready.\n".utf8))
            try await Task.sleep(for: .seconds(90)); window.close()
        }
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height)); host.sizingOptions = []
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); renders += 1
    }
}
private struct StatsGraphPanel: View {
    let snapshot: StatsSnapshot
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                card {
                    StatsBarChart(title: "Your focus over time", points: snapshot.buckets.enumerated().map {
                        .init(id: $0.offset, label: $0.element.label, seconds: $0.element.seconds, projects: $0.element.projects)
                    }, plotHeight: 250)
                }
                card {
                    StatsBarChart(title: "Focus by weekday", points: snapshot.weekdays.enumerated().map {
                        .init(id: $0.offset, label: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][$0.offset], seconds: $0.element)
                    }, color: KeepTheme.sageInk)
                }
                card {
                    StatsBarChart(title: "Focus by hour", points: snapshot.todayHours.enumerated().map {
                        .init(id: $0.offset, label: String(format: "%02d:00", $0.offset), seconds: $0.element)
                    }, subtitle: "Today · Tue, 13 Oct 2026")
                }
            }.padding(24)
        }.background(KeepTheme.paper).foregroundStyle(KeepTheme.ink)
    }
    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content().padding(20).frame(maxWidth: .infinity).background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
    }
}
private final class StatsGraphRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await StatsGraphChecks.run() }
            catch { preconditionFailure("Stats graph checks failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
