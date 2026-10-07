import Foundation

/// Optimized, isolated fixtures; advances the existing recorder by 60 seconds.
/// --realtime paces the same injected-clock ticks over one actual minute per fixture.
/// Run baseline/cached in separate processes to measure CPU and peak memory independently.
@main enum CacheBenchmarks {
    nonisolated struct Fixture: Encodable {
        let entries: [TimesheetEntry]
        let sessions: [RecordedSession]
        let customProjects: [FocusProject]
        let taskActivities: [TaskActivity] = []
    }
    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }
    static func report(_ label: String, _ values: [Double]) {
        let sorted = values.sorted()
        print("\(label) median_ms=\(sorted[sorted.count / 2]) p95_ms=\(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))])")
    }
    static func ledger(records: [RecordedSession], projects: [FocusProject]) throws -> TimesheetLedger {
        try autoreleasepool {
            let entries = Dictionary(grouping: records, by: { "\($0.project.id)/\($0.dayID)" }).compactMap { _, values -> TimesheetEntry? in
                guard let first = values.first else { return nil }
                return .init(project: first.project, dayID: first.dayID, seconds: values.reduce(0) { $0 + $1.seconds })
            }
            return try JSONDecoder().decode(TimesheetLedger.self, from: JSONEncoder().encode(Fixture(entries: entries, sessions: records, customProjects: projects)))
        }
    }
    static func workspace(records: [RecordedSession], projects: [FocusProject], calendar: Calendar, now: Date) throws -> (WorkspaceModel, Double) {
        let ledger = try ledger(records: records, projects: projects)
        let start = ContinuousClock.now
        let owner = WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
        return (owner, milliseconds(start))
    }
    static func residentKiB() throws -> String {
        let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]; process.standardOutput = pipe
        try process.run(); let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func main() async throws {
        let cached = !CommandLine.arguments.contains("--baseline")
        let realtime = CommandLine.arguments.contains("--realtime")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt; calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12)) ?? .now
        for count in [1_000, 10_000, 50_000] {
            let projects = (0..<10).map { FocusProject(id: "p\($0)", name: "Project \($0)", accent: .sage, category: "Fixture") }
            let records: [RecordedSession] = (0..<count).map { i in
                let start = now.addingTimeInterval(-Double(i / 100) * 86400 - Double(i % 100) * 60 - 60)
                return .init(id: "s\(i)", recordingID: UUID(), dayID: StatsSnapshot.dayID(start, calendar: calendar), project: projects[i % 10],
                             task: "Task \(i % 20)", source: .flow, timeZoneID: "GMT", start: start, end: start.addingTimeInterval(30))
            }
            let statsProjects = projects.map { StatsInput.Project(id: $0.id, name: $0.name, accent: $0.accent.rawValue, deleted: false) }
            var preparation: [Double] = [], aggregation: [Double] = [], navigation: [Double] = [], checksum = 0.0
            if !cached {
                let ledger = try ledger(records: records, projects: projects)
                var live = ledger.sessions.map { StatsInput.Session(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, start: $0.start, end: $0.end, timeZoneID: $0.timeZoneID) }
                for tick in 1...60 {
                    if realtime { try await Task.sleep(for: .seconds(1)) }
                    if tick > 1 { live.removeLast() }
                    live.append(.init(projectID: projects[0].id, task: "Task 0", dayID: "2026-10-07", start: now, end: now.addingTimeInterval(Double(tick)), timeZoneID: "GMT"))
                    let start = ContinuousClock.now
                    let input = StatsInput(query: StatsQuery(), now: now.addingTimeInterval(Double(tick)), calendar: calendar, projects: statsProjects,
                        sessions: live.map { .init(projectID: $0.projectID, task: $0.task, dayID: $0.dayID, start: $0.start, end: $0.end, timeZoneID: $0.timeZoneID) },
                        completions: [], historyStartedAt: now, entries: ledger.entries.map { .init(projectID: $0.project.id, dayID: $0.dayID, seconds: $0.seconds) }, tasks: [], habits: [])
                    preparation.append(milliseconds(start))
                    let calculation = ContinuousClock.now; checksum += try StatsSnapshot.make(input).total; aggregation.append(milliseconds(calculation))
                }
                var month = StatsQuery(); month.period = .month
                var year = StatsQuery(); year.period = .year
                var project = StatsQuery(); project.projectID = "p0"
                let queries = [StatsQuery(), month, year, project]
                for iteration in 0..<44 {
                    let start = ContinuousClock.now
                    _ = try StatsSnapshot.make(StatsInput(query: queries[iteration % 4], now: now.addingTimeInterval(60), calendar: calendar, projects: statsProjects,
                        sessions: live, completions: [], historyStartedAt: now, entries: [], tasks: [], habits: []))
                    if iteration >= 4 { navigation.append(milliseconds(start)) }
                }
                report("baseline sessions=\(count) warm_navigation", navigation)
                let week = TimesheetWeek(containing: now, calendar: calendar)
                var weekly: [Double] = [], weeklyChecksum = 0.0
                for _ in 0..<60 {
                    let start = ContinuousClock.now
                    let sessions = ledger.sessions.filter { week.dayIDs.contains($0.dayID) }
                    for day in week.days { weeklyChecksum += sessions.filter { $0.dayID == day.id }.sorted { $0.start < $1.start }.reduce(0) { $0 + $1.seconds } }
                    weekly.append(milliseconds(start))
                }
                report("baseline sessions=\(count) weekly_query", weekly)
                print("baseline sessions=\(count) weekly_checksum=\(weeklyChecksum) rss_kib=\(try residentKiB())")
            } else {
                let indexStart = ContinuousClock.now
                let (workspace, indexMilliseconds) = try workspace(records: records, projects: projects, calendar: calendar, now: now)
                print("cached sessions=\(count) cold_index_ms=\(indexMilliseconds) fixture_load_ms=\(milliseconds(indexStart))")
                let clock = ContinuousClock.now, cache = StatsCache()
                workspace.selectProject(projects[0], at: clock, date: now)
                workspace.setTaskName("Task 0", at: clock, date: now); workspace.play(.flow, at: clock, date: now)
                let supplement = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
                var initial = workspace.readIndex.batch(since: nil, epoch: nil)
                let coldStart = ContinuousClock.now
                _ = try await cache.snapshot(batch: initial, query: StatsQuery(), supplement: supplement, now: now, calendar: calendar)
                print("cached sessions=\(count) cold_query_ms=\(milliseconds(coldStart))")
                var revision = initial.revision
                initial = workspace.readIndex.batch(since: revision, epoch: initial.epoch)
                for tick in 1...60 {
                    if realtime { try await Task.sleep(for: .seconds(1)) }
                    workspace.synchronize(at: clock + .seconds(tick), date: now.addingTimeInterval(Double(tick)))
                    let start = ContinuousClock.now
                    let batch = workspace.readIndex.batch(since: revision, epoch: initial.epoch)
                    preparation.append(milliseconds(start))
                    let calculation = ContinuousClock.now
                    checksum += try await cache.snapshot(batch: batch, query: StatsQuery(), supplement: supplement, now: now.addingTimeInterval(Double(tick)), calendar: calendar).total
                    aggregation.append(milliseconds(calculation)); revision = batch.revision
                }
                let baseline = await cache.preparations
                print("cached sessions=\(count) query_preparations_during_ticks=\(baseline - 1)")
                var month = StatsQuery(); month.period = .month
                var year = StatsQuery(); year.period = .year
                var project = StatsQuery(); project.projectID = "p0"
                let queries = [StatsQuery(), month, year, project]
                let batch = workspace.readIndex.batch(since: revision, epoch: initial.epoch)
                for query in queries { _ = try await cache.snapshot(batch: batch, query: query, supplement: supplement, now: now.addingTimeInterval(60), calendar: calendar) }
                let builds = await cache.preparations
                for iteration in 0..<40 {
                    let start = ContinuousClock.now
                    _ = try await cache.snapshot(batch: batch, query: queries[iteration % 4], supplement: supplement, now: now.addingTimeInterval(60), calendar: calendar)
                    navigation.append(milliseconds(start))
                }
                print("cached sessions=\(count) warm_navigation_preparations=\(await cache.preparations - builds) retained_queries=\(await cache.queryCount)")
                report("cached sessions=\(count) warm_navigation", navigation)
                let dashboard = DashboardQueryModel(), week = TimesheetWeek(containing: now, calendar: calendar)
                dashboard.refresh(week: week, index: workspace.readIndex, calendar: calendar)
                var weekly: [Double] = []
                for _ in 0..<60 { let start = ContinuousClock.now; dashboard.refresh(week: week, index: workspace.readIndex, calendar: calendar); weekly.append(milliseconds(start)) }
                report("cached sessions=\(count) weekly_hit", weekly)
                print("cached sessions=\(count) rss_kib=\(try residentKiB())")
            }
            report("\(cached ? "cached" : "baseline") sessions=\(count) preparation", preparation)
            report("\(cached ? "cached" : "baseline") sessions=\(count) aggregation", aggregation)
            print("\(cached ? "cached" : "baseline") sessions=\(count) checksum=\(checksum)")
        }
    }
}
