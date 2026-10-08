import Foundation

nonisolated struct StatsSupplement: Sendable {
    let taskRevision: UInt64
    let habitRevision: UInt64
    let tasks: [StatsInput.TaskDay]
    let habits: [StatsInput.Habit]
}

/// One worker per window. Historical work is prepared once, then patched by record identity.
/// It owns no clocks, stores, or recording behavior. Cancellation only discards presentation work.
actor StatsCache {
    private var sessions: [String: Session] = [:]
    private var completions: [UUID: CompletedPomodoro] = [:]
    private var entries: [String: TimesheetEntry] = [:]
    private var projects: [StatsInput.Project] = []
    private var epoch: UUID?
    private var revision: UInt64?
    private var historyStartedAt: Date?
    private var sequence = 0
    private var queries: [PreparedQuery] = []
    private var sections: [Sections] = []
    private var calendarContext: Calendar?
    private var localeContext: String?
    private var lastNow: Date?
    private(set) var preparations = 0
    private(set) var taskPreparations = 0
    private(set) var habitPreparations = 0
    var queryCount: Int { queries.count }

    func snapshot(batch: WorkspaceReadBatch, query: StatsQuery, supplement: StatsSupplement,
                  now: Date, calendar source: Calendar) throws -> StatsSnapshot {
        try Task.checkCancellation()
        let calendar = StatsSnapshot.calendar(source)
        let locale = calendar.locale?.identifier ?? Locale.current.identifier
        if calendarContext != calendar || localeContext != locale || lastNow.map({ now < $0 }) == true {
            queries = []; sections = []
            for session in sessions.values { session.hours = nil }
        }
        calendarContext = calendar; localeContext = locale; lastNow = now
        // Apply the complete batch before checking cancellation again, so a canceled request
        // cannot leave the worker's revision ahead of a partially applied mutation feed.
        apply(batch, calendar: calendar)
        try Task.checkCancellation()
        let range = query.range(now: now, calendar: calendar)
        let today = StatsSnapshot.dayID(now, calendar: calendar)
        let prepared: PreparedQuery
        if let position = queries.firstIndex(where: { $0.query.period == query.period && $0.query.projectID == query.projectID && $0.query.taskKeys == query.taskKeys && $0.range == range && $0.today == today }) {
            prepared = queries.remove(at: position)
        } else {
            prepared = try PreparedQuery(query: query, range: range, now: now, calendar: calendar, projects: projects)
            for session in sessions.values.sorted(by: { $0.order < $1.order }) {
                try Task.checkCancellation()
                prepared.replace(old: nil, new: session, now: now)
            }
            for completion in completions.values { prepared.replaceCompletion(old: nil, new: completion) }
            for entry in entries.values { prepared.replaceEntry(old: nil, new: entry) }
            preparations += 1
        }
        // On failure/cancellation, an entry removed from the LRU is discarded rather than
        // retaining partially refreshed state. The immutable source index remains complete.
        try prepared.advance(to: now, sessions: sessions, completions: completions)
        let summary = try summary(query: query, range: range, today: today, supplement: supplement, now: now, calendar: calendar)
        let result = try prepared.snapshot(summary: summary, historyStartedAt: historyStartedAt)
        try Task.checkCancellation()
        queries.append(prepared)
        if queries.count > 4 { queries.removeFirst(queries.count - 4) }
        return result
    }

    private func apply(_ batch: WorkspaceReadBatch, calendar: Calendar) {
        if epoch == batch.epoch, let revision, batch.revision <= revision { return }
        if batch.reset || epoch != batch.epoch {
            sessions = [:]; completions = [:]; entries = [:]; queries = []; sequence = 0
        } else if let revision, batch.revision <= revision { return }
        if projects != batch.projects { queries = [] }
        projects = batch.projects; historyStartedAt = batch.historyStartedAt
        let changes = batch.updates.filter { batch.reset || $0.revision > (revision ?? 0) }.flatMap(\.changes)
        for change in changes {
            switch change {
            case .session(let record):
                let old = sessions[record.id]
                let new = Session(record: record, order: old?.order ?? sequence)
                if old == nil { sequence += 1 }
                if let old, let hours = old.hours, old.record.start == record.start,
                   old.record.timeZoneID == record.timeZoneID, record.end >= old.record.end {
                    new.hours = hours
                    new.addHours(from: old.record.end, to: record.end, calendar: calendar)
                }
                for query in queries { query.replace(old: old, new: new, now: query.now) }
                sessions[record.id] = new
            case .removeSession(let record):
                let old = sessions.removeValue(forKey: record.id)
                for query in queries { query.replace(old: old, new: nil, now: query.now) }
            case .entry(let entry):
                let old = entries.updateValue(entry, forKey: entry.id)
                for query in queries { query.replaceEntry(old: old, new: entry) }
            case .removeEntry(let entry):
                let old = entries.removeValue(forKey: entry.id)
                for query in queries { query.replaceEntry(old: old, new: nil) }
            case .completion(let completion):
                let old = completions.updateValue(completion, forKey: completion.id)
                for query in queries { query.replaceCompletion(old: old, new: completion) }
            case .activity, .catalog, .coverage: break
            }
        }
        epoch = batch.epoch; revision = batch.revision
    }

    private func summary(query: StatsQuery, range: StatsRange, today: String, supplement: StatsSupplement,
                         now: Date, calendar: Calendar) throws -> Sections {
        let value: Sections
        if let index = sections.firstIndex(where: { $0.range == range && $0.today == today }) { value = sections.remove(at: index) }
        else { value = Sections(range: range, today: today) }
        var datesOnly = query; datesOnly.projectID = nil; datesOnly.taskKeys = nil
        func input(tasks: [StatsInput.TaskDay], habits: [StatsInput.Habit]) -> StatsInput {
            StatsInput(query: datesOnly, now: now, calendar: calendar, projects: [], sessions: [], completions: [], historyStartedAt: nil,
                       entries: [], tasks: tasks, habits: habits)
        }
        if value.taskRevision != supplement.taskRevision {
            let snapshot = try StatsSnapshot.make(input(tasks: supplement.tasks, habits: []))
            value.tasksTotal = snapshot.tasksTotal; value.tasksCompleted = snapshot.tasksCompleted
            value.taskRevision = supplement.taskRevision
            taskPreparations += 1
        }
        if value.habitRevision != supplement.habitRevision {
            value.habits = try StatsSnapshot.make(input(tasks: [], habits: supplement.habits)).habits
            value.habitRevision = supplement.habitRevision
            habitPreparations += 1
        }
        sections.append(value)
        if sections.count > 4 { sections.removeFirst(sections.count - 4) }
        return value
    }

    nonisolated private final class Sections {
        let range: StatsRange
        let today: String
        var taskRevision: UInt64?, habitRevision: UInt64?
        var tasksTotal = 0, tasksCompleted = 0
        var habits: [StatsSnapshot.Habit] = []
        init(range: StatsRange, today: String) { self.range = range; self.today = today }
    }

    nonisolated private final class Session {
        let record: RecordedSession
        let order: Int
        var hours: [Double]?
        init(record: RecordedSession, order: Int) { self.record = record; self.order = order }
        func hourValues(until end: Date, calendar: Calendar) -> [Double] {
            if end == record.end {
                if hours == nil { hours = Array(repeating: 0, count: 24); addHours(from: record.start, to: end, calendar: calendar) }
                return hours ?? Array(repeating: 0, count: 24)
            }
            return Self.split(from: record.start, to: end, timeZoneID: record.timeZoneID, calendar: calendar)
        }
        func addHours(from start: Date, to end: Date, calendar: Calendar) {
            let extra = Self.split(from: start, to: end, timeZoneID: record.timeZoneID, calendar: calendar)
            if hours == nil { hours = Array(repeating: 0, count: 24) }
            for index in 0..<24 { hours?[index] += extra[index] }
        }
        static func split(from start: Date, to end: Date, timeZoneID: String, calendar: Calendar) -> [Double] {
            var local = calendar; local.timeZone = TimeZone(identifier: timeZoneID) ?? calendar.timeZone
            var result = Array(repeating: 0.0, count: 24), cursor = start
            while cursor < end {
                guard let hour = local.dateInterval(of: .hour, for: cursor), hour.end > cursor else { break }
                let stop = min(hour.end, end)
                result[local.component(.hour, from: cursor)] += stop.timeIntervalSince(cursor); cursor = stop
            }
            return result
        }
    }

    nonisolated private final class Group {
        var seconds = 0.0
        private var names: [String: (order: Int, name: String)] = [:]
        private(set) var first: (id: String, order: Int, name: String)?
        var isEmpty: Bool { names.isEmpty }
        func add(id: String, order: Int, name: String) {
            names[id] = (order, name)
            if first == nil || order < (first?.order ?? Int.max) { first = (id, order, name) }
        }
        func remove(id: String) {
            names.removeValue(forKey: id)
            if first?.id == id {
                first = names.min(by: { $0.value.order < $1.value.order }).map { ($0.key, $0.value.order, $0.value.name) }
            }
        }
        let projectID: String
        let taskKey: String?
        let accent: String
        init(projectID: String, taskKey: String?, accent: String) { self.projectID = projectID; self.taskKey = taskKey; self.accent = accent }
    }

    nonisolated private final class PreparedQuery {
        let query: StatsQuery, range: StatsRange, today: String, calendar: Calendar
        let startID: String, effectiveEnd: String, previousStart: String, previousEnd: String
        let weekStart: String, weekEnd: String
        let projectMap: [String: StatsInput.Project]
        let hasWallCutoff: Bool
        var now: Date
        // Positive-session counts avoid rounding residuals changing active days or streaks.
        let activityLayout: FocusActivitySnapshot
        var activityDaily: [String: Double] = [:]
        var daily: [String: Double] = [:]
        var groups: [String: Group] = [:]
        var total = 0.0, previousTotal = 0.0, weeklyGoal = 0.0, adjusted = 0.0
        var activeDays = 0, pomodoros = 0
        var weekdays = Array(repeating: 0.0, count: 7), hours = Array(repeating: 0.0, count: 24)
        var buckets: [StatsSnapshot.Bucket] = []
        var bucketByDay: [String: Int] = [:]
        var dynamicSessions: Set<String> = [], dynamicCompletions: Set<UUID> = []
        var streakDirty = true
        var streak = (current: 0, best: 0)

        init(query: StatsQuery, range: StatsRange, now: Date, calendar: Calendar, projects: [StatsInput.Project]) throws {
            activityLayout = FocusActivitySnapshot(range: range, now: now, calendar: calendar)
            self.query = query; self.range = range; self.now = now; self.calendar = calendar
            today = StatsSnapshot.dayID(now, calendar: calendar)
            startID = StatsSnapshot.dayID(range.start, calendar: calendar)
            effectiveEnd = min(StatsSnapshot.dayID(range.endDay(calendar: calendar), calendar: calendar), today)
            let previous = StatsSnapshot.comparisonRange(query: query, range: range, now: now, calendar: calendar)
            previousStart = StatsSnapshot.dayID(previous.range.start, calendar: calendar)
            previousEnd = StatsSnapshot.dayID(previous.range.endDay(calendar: calendar), calendar: calendar)
            hasWallCutoff = previous.wallCutoff != nil
            let week = StatsQuery().range(now: now, calendar: calendar)
            weekStart = StatsSnapshot.dayID(week.start, calendar: calendar)
            weekEnd = min(StatsSnapshot.dayID(week.endDay(calendar: calendar), calendar: calendar), today)
            projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            // Date labels and zero buckets are stable for this query/day/calendar context.
            let count = calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0
            let grouping: Calendar.Component = query.period == .year || (query.period == .custom && count > 180) ? .month : query.period == .custom && count > 31 ? .weekOfYear : .day
            let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = calendar.locale
            formatter.dateFormat = grouping == .month ? "MMM yyyy" : "d MMM"
            var cursor = range.start, indices: [String: Int] = [:]
            while cursor < range.end {
                try Task.checkCancellation()
                let date = max(range.start, calendar.dateInterval(of: grouping, for: cursor)?.start ?? cursor)
                let key = StatsSnapshot.dayID(date, calendar: calendar)
                if indices[key] == nil {
                    indices[key] = buckets.count
                    buckets.append(.init(id: key, date: date, label: formatter.string(from: date), seconds: 0))
                }
                bucketByDay[StatsSnapshot.dayID(cursor, calendar: calendar)] = indices[key]
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }; cursor = next
            }
        }

        func matches(_ project: String, _ task: String) -> Bool {
            (query.projectID == nil || query.projectID == project) && (query.taskKeys?.contains(StatsQuery.taskKey(task)) ?? true)
        }
        func selected(_ day: String) -> Bool { day >= startID && day <= effectiveEnd }
        func replace(old: Session?, new: Session?, now: Date) {
            let days = Set([old?.record.dayID, new?.record.dayID].compactMap { $0 })
            let before = Dictionary(uniqueKeysWithValues: days.map { ($0, daily[$0, default: 0] > 0) })
            if let old { apply(old, factor: -1, now: now); dynamicSessions.remove(old.record.id) }
            if let new {
                apply(new, factor: 1, now: now)
                if new.record.end > now || (hasWallCutoff && new.record.dayID == previousEnd && matches(new.record.project.id, new.record.task)) {
                    dynamicSessions.insert(new.record.id)
                }
            }
            if days.contains(where: { before[$0] != (daily[$0, default: 0] > 0) }) { streakDirty = true }
        }

        private func apply(_ session: Session, factor: Double, now: Date) {
            let record = session.record
            let end = min(record.end, now), seconds = max(0, end.timeIntervalSince(record.start))
            if record.dayID >= weekStart && record.dayID <= weekEnd { weeklyGoal += seconds * factor }
            guard matches(record.project.id, record.task) else { return }
            if record.dayID >= previousStart && record.dayID <= previousEnd {
                var previousSeconds = record.seconds
                if record.dayID == previousEnd && hasWallCutoff {
                    var local = calendar; local.timeZone = TimeZone(identifier: record.timeZoneID) ?? calendar.timeZone
                    let wall = calendar.dateComponents([.hour, .minute, .second], from: now)
                    if let day = StatsSnapshot.date(previousEnd, calendar: local),
                       let cutoff = local.date(bySettingHour: wall.hour ?? 0, minute: wall.minute ?? 0, second: wall.second ?? 0, of: day) {
                        previousSeconds = max(0, min(record.end, cutoff).timeIntervalSince(record.start))
                    }
                }
                previousTotal += max(0, previousSeconds) * factor
            }
            if record.dayID <= effectiveEnd && seconds > 0 {
                let wasActive = daily[record.dayID, default: 0] > 0
                daily[record.dayID, default: 0] += factor
                if daily[record.dayID] == 0 { daily.removeValue(forKey: record.dayID) }
                if selected(record.dayID) {
                    let isActive = daily[record.dayID, default: 0] > 0
                    if wasActive != isActive { activeDays += isActive ? 1 : -1 }
                }
            }
            guard selected(record.dayID), seconds > 0 else { return }
            activityDaily[record.dayID, default: 0] += seconds * factor
            total += seconds * factor
            if let index = bucketByDay[record.dayID] { buckets[index].seconds += seconds * factor }
            let key = query.projectID == nil ? record.project.id : StatsQuery.taskKey(record.task)
            let group = groups[key] ?? Group(projectID: record.project.id, taskKey: query.projectID == nil ? nil : key, accent: projectMap[record.project.id]?.accent ?? "neutral")
            group.seconds += seconds * factor
            if factor > 0 {
                group.add(id: record.id, order: session.order, name: query.projectID == nil ? (projectMap[record.project.id]?.name ?? "No project") : (record.task.isEmpty ? "Unnamed task" : record.task))
            } else { group.remove(id: record.id) }
            groups[key] = group.isEmpty ? nil : group
            if let day = StatsSnapshot.date(record.dayID, calendar: calendar) {
                weekdays[(calendar.component(.weekday, from: day) + 5) % 7] += seconds * factor
            }
            let values = session.hourValues(until: end, calendar: calendar)
            for index in 0..<24 { hours[index] += values[index] * factor }
        }

        func replaceEntry(old: TimesheetEntry?, new: TimesheetEntry?) {
            if let old, selected(old.dayID), query.projectID == nil || query.projectID == old.project.id { adjusted -= old.seconds }
            if let new, selected(new.dayID), query.projectID == nil || query.projectID == new.project.id { adjusted += new.seconds }
        }
        func counts(_ event: CompletedPomodoro, now: Date) -> Bool {
            selected(event.dayID) && event.completedAt <= now && matches(event.project.id, event.task)
        }
        func replaceCompletion(old: CompletedPomodoro?, new: CompletedPomodoro?) {
            if let old { if counts(old, now: now) { pomodoros -= 1 }; dynamicCompletions.remove(old.id) }
            if let new {
                if counts(new, now: now) { pomodoros += 1 }
                if selected(new.dayID) && new.completedAt > now { dynamicCompletions.insert(new.id) }
            }
        }
        func advance(to date: Date, sessions: [String: Session], completions: [UUID: CompletedPomodoro]) throws {
            guard date != now else { return }
            for id in dynamicSessions {
                try Task.checkCancellation()
                guard let session = sessions[id] else { continue }
                let day = session.record.dayID, wasActive = daily[session.record.dayID, default: 0] > 0
                apply(session, factor: -1, now: now)
                apply(session, factor: 1, now: date)
                if wasActive != (daily[day, default: 0] > 0) { streakDirty = true }
                if session.record.end <= date && !(hasWallCutoff && day == previousEnd && matches(session.record.project.id, session.record.task)) {
                    dynamicSessions.remove(id)
                }
            }
            for id in dynamicCompletions {
                guard let event = completions[id] else { continue }
                if !counts(event, now: now) && counts(event, now: date) { pomodoros += 1; dynamicCompletions.remove(id) }
            }
            now = date
        }
        func snapshot(summary: Sections, historyStartedAt: Date?) throws -> StatsSnapshot {
            if streakDirty {
                streak = try StatsSnapshot.focusStreak(daily: daily, startID: startID, endID: effectiveEnd, todayID: today, calendar: calendar)
                streakDirty = false
            }
            let distribution: [StatsSnapshot.Distribution] = groups.compactMap { key, group in
                guard let first = group.first else { return nil }
                return .init(id: key, name: first.name, projectID: group.projectID, taskKey: group.taskKey, accent: group.accent, seconds: group.seconds)
            }.sorted { $0.seconds == $1.seconds ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.seconds > $1.seconds }
            return StatsSnapshot(range: range, total: max(0, total), previousTotal: max(0, previousTotal), activeDays: activeDays,
                pomodoros: pomodoros, pomodorosAvailable: historyStartedAt.map { StatsSnapshot.dayID($0, calendar: calendar) <= effectiveEnd } ?? false,
                adjustedTotal: max(0, adjusted), focusActivity: activityLayout.filling(activityDaily), buckets: buckets, distribution: distribution, weekdays: weekdays, hours: hours,
                tasksCompleted: summary.tasksCompleted, tasksTotal: summary.tasksTotal, habits: summary.habits, weeklyGoalSeconds: max(0, weeklyGoal),
                currentStreak: streak.current, bestStreak: streak.best)
        }
    }
}
