import Foundation

@main enum CacheChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }
    static func equivalent(_ a: StatsSnapshot, _ b: StatsSnapshot, _ message: String) {
        expect(a.range == b.range && close(a.total, b.total) && close(a.previousTotal, b.previousTotal)
            && a.activeDays == b.activeDays && a.pomodoros == b.pomodoros && a.pomodorosAvailable == b.pomodorosAvailable
            && close(a.adjustedTotal, b.adjustedTotal) && close(a.weeklyGoalSeconds, b.weeklyGoalSeconds)
            && a.tasksCompleted == b.tasksCompleted && a.tasksTotal == b.tasksTotal && a.habits == b.habits
            && a.currentStreak == b.currentStreak && a.bestStreak == b.bestStreak
            && Set(a.dailyFocus.keys).union(b.dailyFocus.keys).allSatisfy { close(a.dailyFocus[$0, default: 0], b.dailyFocus[$0, default: 0]) }
            && close(a.focusActivity.seconds, b.focusActivity.seconds)
            && zip(a.focusActivity.weeks.flatMap(\.days), b.focusActivity.weeks.flatMap(\.days)).allSatisfy { $0.id == $1.id && close($0.seconds, $1.seconds) }
            && a.buckets.map(\.id) == b.buckets.map(\.id) && zip(a.buckets, b.buckets).allSatisfy { close($0.seconds, $1.seconds) }
            && a.distribution.map(\.id) == b.distribution.map(\.id) && a.distribution.map(\.name) == b.distribution.map(\.name)
            && zip(a.distribution, b.distribution).allSatisfy { close($0.seconds, $1.seconds) }
            && zip(a.hours, b.hours).allSatisfy(close) && zip(a.weekdays, b.weekdays).allSatisfy(close), message)
    }
    static func supplement(_ tasks: DailyTaskStore, _ habits: HabitStore) -> StatsSupplement {
        let logs = Dictionary(grouping: habits.archive.logs, by: \.habitID)
        return .init(taskRevision: tasks.revision, habitRevision: habits.revision,
            tasks: tasks.archive.days.map { day, rows in
                let ordinary = rows.filter { $0.habitID == nil }
                return .init(dayID: day, total: ordinary.count, completed: ordinary.filter(\.isComplete).count)
            }, habits: habits.habits.map {
                .init(id: $0.id, name: $0.name, icon: $0.icon.rawValue, start: $0.startDay, end: $0.endDay,
                      weekdays: Set($0.weekdays.map(\.rawValue)), target: $0.goal.target,
                      progress: Dictionary(uniqueKeysWithValues: logs[$0.id, default: []].map { ($0.dayID, $0.amount) }))
            })
    }
    static func reference(_ workspace: WorkspaceModel, query: StatsQuery, supplement: StatsSupplement, now: Date, calendar: Calendar) throws -> StatsSnapshot {
        try StatsSnapshot.make(StatsInput(query: query, now: now, calendar: calendar, projects: workspace.readIndex.statsProjects,
            sessions: workspace.ledger.sessions.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, start: $0.start, end: $0.end, timeZoneID: $0.timeZoneID) },
            completions: workspace.ledger.completedPomodoros.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, date: $0.completedAt) },
            historyStartedAt: workspace.ledger.pomodoroHistoryStartedAt,
            entries: workspace.ledger.entries.map { .init(projectID: $0.project.id, dayID: $0.dayID, seconds: $0.seconds) }, tasks: supplement.tasks, habits: supplement.habits))
    }
    static func main() async throws {
        try await historyChecks()
        try await musicChecks()
        print("Passed \(checks) cache correctness, invalidation, lifecycle and retention checks")
    }

    static func historyChecks() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt; calendar.firstWeekday = 2
        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
        }
        let now = date(7, 10, 30), instant = ContinuousClock.now
        let tinyStart = date(6, 12)
        let tinyEnd = Date(timeIntervalSinceReferenceDate: tinyStart.timeIntervalSinceReferenceDate.nextUp)
        var tinyLedger = TimesheetLedger()
        tinyLedger.record(project: .unassigned, from: tinyStart, seconds: tinyEnd.timeIntervalSince(tinyStart), calendar: calendar, sessionID: UUID())
        let tinyWorkspace = WorkspaceModel(ledger: tinyLedger, calendar: calendar, date: now)
        let tinySupplement = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
        let tiny = try await StatsCache().snapshot(batch: tinyWorkspace.readIndex.batch(since: nil, epoch: nil), query: StatsQuery(), supplement: tinySupplement, now: now, calendar: calendar)
        equivalent(tiny, try reference(tinyWorkspace, query: StatsQuery(), supplement: tinySupplement, now: now, calendar: calendar), "Every positive interval retains active-day and streak semantics")
        expect(tiny.activeDays == 1, "Sub-microsecond positive recorded time still makes a day active")
        var ledger = TimesheetLedger()
        for (day, month, task) in [(5, 10, "Hören"), (6, 10, " hören "), (30, 9, "Hören"), (28, 9, "")] {
            ledger.record(project: .defaults[1], from: date(day, 10, month: month), seconds: 3600, calendar: calendar, sessionID: UUID(), task: task)
        }
        ledger.record(project: .unassigned, from: date(7, 10, 45), seconds: 3600, calendar: calendar, sessionID: UUID())
        let workspace = WorkspaceModel(ledger: ledger, calendar: calendar, focusDuration: 10, date: now)
        let habits = HabitStore(calendar: calendar), tasks = DailyTaskStore(calendar: calendar, habits: habits)
        let habit = try habits.add(name: "Read", icon: .allCases[0], startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        _ = habits.setAmount(1, habitID: habit.id, on: "2026-10-05", today: now)
        _ = tasks.add("Saved task", on: "2026-10-05")
        let cache = StatsCache()
        var cursor: (epoch: UUID, revision: UInt64)?
        func check(_ query: StatsQuery = StatsQuery(), at current: Date = now, using source: Calendar? = nil) async throws -> StatsSnapshot {
            let batch = workspace.readIndex.batch(since: cursor?.revision, epoch: cursor?.epoch), values = supplement(tasks, habits)
            let result = try await cache.snapshot(batch: batch, query: query, supplement: values, now: current, calendar: source ?? calendar)
            equivalent(result, try reference(workspace, query: query, supplement: values, now: current, calendar: source ?? calendar), "Cached result must equal reference: \(query.period), \(query.projectID ?? "all"), \(current)")
            cursor = (batch.epoch, batch.revision)
            return result
        }
        let first = try await check()
        let later = try await check(at: now.addingTimeInterval(1))
        expect(later.previousTotal > first.previousTotal, "Idle elapsed-period comparison advances with the clock")
        expect(await cache.preparations == 1, "Idle refresh reuses the historical query")
        var german = StatsQuery(); german.projectID = "german"; german.taskKeys = ["horen", ""]
        _ = try await check(german, at: now.addingTimeInterval(1))
        let firstTaskBuilds = await cache.taskPreparations, firstHabitBuilds = await cache.habitPreparations
        expect(firstTaskBuilds == 1 && firstHabitBuilds == 1, "Project/task filters reuse date-only summaries")
        var custom = StatsQuery(); custom.period = .custom; custom.customStart = date(5); custom.customEnd = date(7)
        _ = try await check(custom, at: now.addingTimeInterval(1))
        let taskBuilds = await cache.taskPreparations, habitBuilds = await cache.habitPreparations
        expect(taskBuilds == 2 && habitBuilds == 2, "Changing dates prepares each date-only summary once")
        workspace.selectProject(.defaults[1], at: instant, date: now)
        workspace.setTaskName("Hören", at: instant, date: now)
        workspace.startBothTimers(at: instant, date: now)
        _ = try await check(at: now)
        let prepared = await cache.preparations
        for tick in 1...60 {
            workspace.synchronize(at: instant + .seconds(tick), date: now.addingTimeInterval(Double(tick)))
            _ = try await check(at: now.addingTimeInterval(Double(tick)))
        }
        expect(await cache.preparations == prepared, "Sixty live ticks patch sessions without rebuilding the query")
        expect(workspace.readIndex.sessions.count == workspace.ledger.sessions.count, "Shared session index tracks appends")
        expect(workspace.ledger.completedPomodoros.count == 1, "Concurrent Flow preserves exactly-once Pomodoro completion")
        let week = TimesheetWeek(containing: now, calendar: calendar), dashboard = DashboardQueryModel()
        func checkWeek() {
            dashboard.refresh(week: week, index: workspace.readIndex, calendar: calendar)
            let projection = dashboard.projection
            expect(close(projection.total, workspace.ledger.total(dayIDs: week.dayIDs)), "Weekly adjusted totals match ledger")
            expect(close(projection.sessionTotal, workspace.ledger.sessions.filter { week.dayIDs.contains($0.dayID) }.reduce(0) { $0 + $1.seconds }), "Weekly Calendar totals match actual sessions")
            expect(projection.projects == workspace.ledger.projects(dayIDs: week.dayIDs), "Weekly rows preserve zero entries and original project metadata")
            for day in week.days {
                expect(close(projection.dayTotals[day.id, default: 0], workspace.ledger.total(dayIDs: [day.id])), "Day total reconciles")
            }
        }
        checkWeek(); let weekBuilds = dashboard.preparations; checkWeek()
        expect(dashboard.preparations == weekBuilds, "Unchanged week is a cache hit")
        let current = now.addingTimeInterval(61), clock = instant + .seconds(61)
        workspace.stopBothTimers(at: clock, date: current)
        workspace.edit(seconds: 12, project: .defaults[1], dayID: "2026-10-05", at: clock, date: current)
        _ = try await check(at: current); checkWeek()
        if let session = workspace.ledger.sessions.first {
            try workspace.editSession(id: session.id, start: session.start, end: session.start.addingTimeInterval(120), at: clock, date: current)
            _ = try await check(at: current); checkWeek()
            try workspace.deleteSession(id: session.id, at: clock, date: current)
            _ = try await check(at: current); checkWeek()
        }
        workspace.removeTimesheetProject(.defaults[1], dayIDs: week.dayIDs, at: clock, date: current)
        _ = try await check(at: current); checkWeek()
        workspace.play(.flow, at: clock, date: current)
        workspace.synchronize(at: clock + .seconds(1), date: current.addingTimeInterval(1))
        workspace.undoTimesheetRemoval(at: clock + .seconds(1), date: current.addingTimeInterval(1))
        _ = try await check(at: current.addingTimeInterval(1)); checkWeek()
        workspace.deleteProject(.defaults[1], at: clock + .seconds(1), date: current.addingTimeInterval(1))
        expect(workspace.readIndex.statsProjects.contains { $0.id == "german" && $0.deleted }, "Deleted project remains available as marked history")
        _ = try await check(german, at: current.addingTimeInterval(1))
        expect(!workspace.taskSuggestions.contains { $0.project.id == "german" }, "Deleted project suggestions disappear")
        if let task = tasks.tasks(on: "2026-10-05").first(where: { $0.habitID == nil }) { tasks.setComplete(true, taskID: task.id, on: "2026-10-05") }
        try habits.updateIdentity(habitID: habit.id, name: "Read a little", icon: .allCases[1])
        _ = try await check(at: current.addingTimeInterval(1))
        var historical = StatsQuery(); historical.anchor = date(28, month: 9)
        _ = try await check(historical, at: current.addingTimeInterval(1))
        workspace.synchronize(at: clock + .seconds(2), date: current.addingTimeInterval(2))
        _ = try await check(historical, at: current.addingTimeInterval(2))
        for offset in 0..<12 {
            historical.anchor = calendar.date(byAdding: .weekOfYear, value: -offset, to: now)
            _ = try await check(historical, at: current.addingTimeInterval(2))
            dashboard.refresh(week: TimesheetWeek(containing: historical.anchor ?? now, calendar: calendar), index: workspace.readIndex, calendar: calendar)
        }
        expect(await cache.queryCount == 4 && dashboard.cachedWeekCount == 8, "Query retention remains bounded")
        let independent = DashboardQueryModel(); independent.refresh(week: week, index: workspace.readIndex, calendar: calendar)
        expect(independent.cachedWeekCount == 1, "Each window owns its browsed-week cache")
        var utc = calendar; utc.timeZone = .gmt; utc.locale = Locale(identifier: "de_DE")
        _ = try await check(at: current.addingTimeInterval(2), using: utc)
        // Hidden windows can fall behind the bounded mutation feed, then safely rebuild.
        let oldRevision = workspace.readIndex.revision, epoch = workspace.readIndex.epoch
        for tick in 3...140 { workspace.synchronize(at: clock + .seconds(tick), date: current.addingTimeInterval(Double(tick))) }
        expect(workspace.readIndex.batch(since: oldRevision, epoch: epoch).reset, "Expired mutation cursor requests a full reset")
        _ = try await check(at: current.addingTimeInterval(140))
        let bytes = try JSONEncoder().encode(workspace.ledger)
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
        expect(object["changes"] == nil && object["revision"] == nil, "Runtime cache state is never archived")
        let reloaded = try JSONDecoder().decode(TimesheetLedger.self, from: bytes)
        workspace.readIndex.rebuild(reloaded)
        _ = try await check(at: current.addingTimeInterval(140))
        expect(workspace.readIndex.epoch != epoch, "Reload fences prior cursors")
        workspace.shutdown(at: clock + .seconds(140), date: current.addingTimeInterval(140))

        // DST gaps/repeated hours, leap years, travel and midnight use the reference rules.
        for (day, month, year, seconds) in [(25, 10, 2026, 14400.0), (29, 3, 2026, 10800.0), (29, 2, 2024, 90000.0)] {
            let start = date(day, 1, month: month, year: year), end = start.addingTimeInterval(seconds + 86400)
            var data = TimesheetLedger()
            data.record(project: .unassigned, from: start, seconds: seconds, calendar: calendar, sessionID: UUID())
            let owner = WorkspaceModel(ledger: data, calendar: calendar, date: end)
            var query = StatsQuery(); query.period = .custom; query.customStart = start; query.customEnd = end
            let empty = StatsSupplement(taskRevision: 0, habitRevision: 0, tasks: [], habits: [])
            let value = try await StatsCache().snapshot(batch: owner.readIndex.batch(since: nil, epoch: nil), query: query, supplement: empty, now: end, calendar: utc)
            equivalent(value, try reference(owner, query: query, supplement: empty, now: end, calendar: utc), "DST/leap/travel cached parity")
        }
        // Preset/custom bucket thresholds and partial scheduled goals retain reference behavior.
        let partial = try habits.add(name: "Practice", icon: .book, startDay: "2026-01-01", endDay: "2026-10-07",
            goal: .amount(target: 10, unit: .minutes), weekdays: [.monday, .wednesday, .friday])
        _ = habits.setAmount(5, habitID: partial.id, on: "2026-10-07", today: now)
        for period in [StatsPeriod.week, .month, .year] {
            var query = StatsQuery(); query.period = period
            _ = try await check(query, at: current.addingTimeInterval(140))
        }
        for length in [1, 31, 32, 180, 181] {
            var query = StatsQuery(); query.period = .custom
            query.customEnd = now; query.customStart = calendar.date(byAdding: .day, value: 1 - length, to: now) ?? now
            _ = try await check(query, at: current.addingTimeInterval(140))
        }
        expect(workspace.readIndex.names(projectID: "german")["horen"] == "Hören", "Task name index preserves activity priority and original casing")
        // Undo may restore an identifier recreated by a recorder: preserve archive order too.
        var collisionLedger = TimesheetLedger()
        collisionLedger.beginPomodoroHistory(at: now)
        let identity = UUID()
        collisionLedger.record(project: .unassigned, from: date(6, 12), seconds: 10, calendar: calendar, sessionID: identity, task: "Hören")
        let removed = collisionLedger.removeSessions(projectID: FocusProject.unassigned.id, dayIDs: ["2026-10-06"])
        collisionLedger.record(project: .unassigned, from: date(6, 13), seconds: 20, calendar: calendar, sessionID: identity, task: "hören")
        _ = collisionLedger.takeChanges()
        let collisionIndex = WorkspaceReadIndex(ledger: collisionLedger), collisionCache = StatsCache()
        var collisionQuery = StatsQuery(); collisionQuery.projectID = FocusProject.unassigned.id
        let initialCollision = collisionIndex.batch(since: nil, epoch: nil)
        _ = try await collisionCache.snapshot(batch: initialCollision, query: collisionQuery, supplement: tinySupplement, now: now, calendar: calendar)
        collisionLedger.restoreSessions(removed)
        collisionIndex.apply(collisionLedger.takeChanges(), ledger: collisionLedger)
        let restored = try await collisionCache.snapshot(batch: collisionIndex.batch(since: initialCollision.revision, epoch: initialCollision.epoch), query: collisionQuery, supplement: tinySupplement, now: now, calendar: calendar)
        equivalent(restored, try reference(WorkspaceModel(ledger: collisionLedger, calendar: calendar, date: now), query: collisionQuery, supplement: tinySupplement, now: now, calendar: calendar), "Colliding Undo preserves original distribution labels and time")
        expect(collisionIndex.names(projectID: FocusProject.unassigned.id)["horen"] == "hören", "Colliding Undo preserves last-source task casing")
        let originalProject = FocusProject(id: "legacy", name: "Original label", accent: .sage, category: "Fixture")
        let laterProject = FocusProject(id: "legacy", name: "Later label", accent: .terracotta, category: "Fixture")
        for (firstDay, secondDay) in [(5, 6), (6, 5)] {
            var oldMetadata = TimesheetLedger()
            oldMetadata.setSeconds(10, project: originalProject, dayID: "2026-10-0\(firstDay)")
            oldMetadata.setSeconds(20, project: laterProject, dayID: "2026-10-0\(secondDay)")
            _ = oldMetadata.takeChanges()
            let index = WorkspaceReadIndex(ledger: oldMetadata)
            expect(WeeklyProjection(days: week.dayIDs, index: index).projects == oldMetadata.projects(dayIDs: week.dayIDs), "Weekly metadata follows archive insertion order regardless of civil-day order")
            let removed = oldMetadata.removeEntries(projectID: "legacy", dayIDs: week.dayIDs)
            oldMetadata.restoreEntries(removed)
            index.apply(oldMetadata.takeChanges(), ledger: oldMetadata)
            expect(WeeklyProjection(days: week.dayIDs, index: index).projects == oldMetadata.projects(dayIDs: week.dayIDs), "Undo retains original weekly project metadata")
        }
        let bounded = WorkspaceReadIndex(ledger: TimesheetLedger()), oldCursor = bounded.revision, oldEpoch = bounded.epoch
        bounded.apply((0..<5000).map { .entry(.init(project: .unassigned, dayID: "2000-01-01", seconds: Double($0))) }, ledger: TimesheetLedger())
        expect(bounded.retainedMutationCount <= 4096 && bounded.batch(since: oldCursor, epoch: oldEpoch).reset, "Large edits bound the mutation feed and force a safe reset")
        let model = StatsModel()
        model.refresh(workspace: workspace, tasks: tasks, habits: habits, now: current)
        model.query.projectID = "no-project"; model.refresh(workspace: workspace, tasks: tasks, habits: habits, now: current)
        model.cancel()
        try await Task.sleep(for: .milliseconds(30))
        expect(model.snapshot == nil, "Canceled worker cannot publish")
        model.refresh(workspace: workspace, tasks: tasks, habits: habits, now: current)
        try await StatsPresentationChecksWait.wait(model)
        expect(model.snapshot != nil, "Hidden page catches up when visible again")
    }

    static func musicChecks() async throws {
        let clock = TestClock(), reads = Reads()
        var cache = AppleMusicLibraryCache(clock: { clock.value })
        func request(_ query: String = "song", _ offset: Int = 0, playlist: AppleMusicItem? = nil) -> AppleMusicLibraryRequest {
            AppleMusicLibraryRequest(query: query, playlist: playlist, offset: offset)
        }
        func load(_ request: AppleMusicLibraryRequest, pid: Int32? = 42, denied: Bool = false, rows: Int = 101) throws -> AppleMusicLibraryPage {
            try cache.load(request, processID: pid, verifyAccess: {
                reads.access += 1; if denied { throw MusicFailure.appleMusicPermission }
            }, readPage: { _ in reads.pages += 1; return .init(items: [], hasMore: false) }, readMetadata: { request in
                reads.metadata += 1
                return (0..<rows).map { .init(item: .init(nativeID: Int32($0), kind: .songs, title: "Song \($0)", artist: "Artist", playlistID: request.playlist?.nativeID), album: "Album") }
            })
        }
        let first = try load(request())
        expect(first.items.count == 50 && first.hasMore, "Search returns the existing page size")
        expect(try load(request()).items == first.items && reads.metadata == 1, "Warm page avoids native metadata reads")
        expect(try load(request("song", 50)).items.first?.nativeID == 50 && reads.metadata == 1, "Search paging shares bulk metadata")
        _ = try load(request("artist")); _ = try load(request("album"))
        expect(reads.metadata == 1 && reads.access == 5, "Different searches share metadata but every request verifies access")
        clock.value = 59; _ = try load(request("Song 10"))
        clock.value = 60; _ = try load(request("Song 10"))
        expect(reads.metadata == 2, "Derived pages expire at original metadata expiry")
        let before = reads.metadata; cache.removeAll(); _ = try load(request())
        expect(reads.metadata == before + 1, "Refresh bypasses successful cached results")
        _ = try load(request(), pid: 43)
        expect(reads.metadata == before + 2, "Music process replacement invalidates native object IDs")
        do { _ = try load(request(), pid: 43, denied: true); preconditionFailure("Access denial must surface") }
        catch MusicFailure.appleMusicPermission { checks += 1 }
        expect(cache.pageCount == 0 && cache.metadataCount == 0, "Access denial clears cached content")
        for index in 0..<30 { _ = try load(request("song \(index)"), pid: 43) }
        expect(cache.pageCount == 24, "Music page LRU is bounded")
        let pageReads = reads.pages; _ = try load(request(""), pid: 43); _ = try load(request(""), pid: 43)
        expect(reads.pages == pageReads + 1, "Ordinary browsing caches pages without bulk prefetch")
        cache.removeAll(); let largeReads = reads.metadata
        _ = try load(request("Song 0"), rows: 20_001); _ = try load(request("Song 1"), rows: 20_001)
        expect(cache.metadataCount == 0 && reads.metadata == largeReads + 2, "Oversized collections remain fully searchable without retention")
        var large = AppleMusicLibraryCache(clock: { 0 })
        _ = try large.load(request(), processID: 1, verifyAccess: {}, readPage: { _ in .init(items: [], hasMore: false) }, readMetadata: { _ in
            [.init(item: .init(nativeID: 1, kind: .songs, title: "Song", artist: String(repeating: "x", count: 8 * 1024 * 1024)), album: "")]
        })
        expect(large.metadataCount == 0, "Metadata byte limit applies independently of item count")
        let canceled = Task { () -> Bool in
            var local = AppleMusicLibraryCache(clock: { 0 })
            do {
                _ = try local.load(request(), processID: 1, verifyAccess: {}, readPage: { _ in .init(items: [], hasMore: false) }, readMetadata: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return [.init(item: .init(nativeID: 1, kind: .songs, title: "Song", artist: ""), album: "")]
                })
                return false
            } catch is CancellationError { return local.pageCount == 0 && local.metadataCount == 0 }
            catch { return false }
        }
        expect(await canceled.value, "Canceled fetches cannot populate the cache")
        var deniedRead = AppleMusicLibraryCache(clock: { 0 })
        do {
            _ = try deniedRead.load(request(), processID: 1, verifyAccess: {}, readPage: { _ in throw MusicFailure.appleMusicPermission }, readMetadata: { _ in throw MusicFailure.appleMusicPermission })
            preconditionFailure("A denied read must surface")
        } catch MusicFailure.appleMusicPermission { expect(deniedRead.pageCount == 0 && deniedRead.metadataCount == 0, "Read-time access failures are never cached") }
        let fake = CachedMusicFake(), model = AppleMusicLibraryModel(controller: fake, launch: {})
        await model.load(request()); await model.load(request(), refreshID: 1)
        expect(await fake.invalidations == 1, "The browser's explicit Refresh reaches the shared controller")
        await model.load(request("album"), refreshID: 1)
        expect(await fake.invalidations == 1, "Typing after Refresh does not repeatedly clear the cache")
    }
}

private enum StatsPresentationChecksWait {
    static func wait(_ model: StatsModel) async throws {
        for _ in 0..<100 { if model.snapshot != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
        preconditionFailure("Snapshot did not publish")
    }
}
nonisolated private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0.0
    var value: Double { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
}
nonisolated private final class Reads { var access = 0, pages = 0, metadata = 0 }
private actor CachedMusicFake: AppleMusicControlling {
    private(set) var invalidations = 0
    func invalidateLibraryCache() { invalidations += 1 }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot { .init(state: .stopped, title: nil, artist: nil) }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage { .init(items: [], hasMore: false) }
}
