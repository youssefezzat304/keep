import Foundation

nonisolated enum ExportReports {
    static func make(_ request: ExportRequest, snapshot s: PersistentSnapshot) throws -> [ExportReport] {
        try request.validate(now: s.capturedAt, calendar: s.calendar)
        try TimesheetPersistence.validate(s.workspace)
        if request.data == .stats { try s.backupPayload().validate() }
        let calendar = s.calendar
        let start = StatsSnapshot.dayID(request.from, calendar: calendar)
        let end = StatsSnapshot.dayID(request.through, calendar: calendar)
        let projects = Dictionary(uniqueKeysWithValues: s.projects.map { ($0.id, $0) })
        func included(_ day: String, _ project: String) -> Bool {
            day >= start && day <= end && (request.projectID == nil || project == request.projectID)
        }
        func projectFields(_ id: String, fallback: String) -> [CSVField] {
            [.text(id), .text(projects[id]?.name ?? fallback), .flag(s.workspace.deletedProjectIDs.contains(id))]
        }
        func report(_ name: String, _ headers: [String], _ rows: [[CSVField]]) throws -> ExportReport {
            .init(filename: name, contents: try CSVReport.encode(headers: headers, rows: rows))
        }
        if request.data == .calendar {
            let rows = s.workspace.sessions.filter {
                included($0.dayID, $0.project.id) && (request.taskKeys?.contains(StatsQuery.taskKey($0.task)) ?? true)
            }.sorted {
                if $0.dayID != $1.dayID { return $0.dayID < $1.dayID }
                return $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
            }.map { session in
                [.text(session.id), .text(session.recordingID.uuidString), .value(session.dayID)] +
                projectFields(session.project.id, fallback: session.project.name) +
                [.text(session.task), .value(session.source.rawValue),
                 .value(timestamp(session.start, zone: session.timeZoneID)), .value(timestamp(session.end, zone: session.timeZoneID)),
                 .text(session.timeZoneID), .number(session.seconds)]
            }
            return [try report(request.filename(calendar: calendar), ["session_id", "recording_id", "civil_day", "project_id", "project_name", "project_deleted", "task", "timer_source", "start", "end", "timezone", "duration_seconds"], rows)]
        }
        // Same project/day attribution as WeeklyProjection. Preserve saved zero entries.
        let recorded = try TimesheetProjectionRules.recordedByEntry(s.workspace.sessions)
        let entries = s.workspace.entries.filter { included($0.dayID, $0.project.id) }.sorted {
            $0.dayID == $1.dayID ? $0.project.id < $1.project.id : $0.dayID < $1.dayID
        }
        let adjustedRows = entries.map { entry in
            [.value(entry.dayID)] + projectFields(entry.project.id, fallback: entry.project.name) +
            [.number(entry.seconds), .number(recorded[entry.id, default: 0])]
        }
        let adjustedHeaders = ["civil_day", "project_id", "project_name", "project_deleted", "adjusted_timesheet_seconds", "recorded_focus_seconds"]
        if request.data == .timesheet { return [try report(request.filename(calendar: calendar), adjustedHeaders, adjustedRows)] }
        guard let tasks = s.tasks, let habits = s.habits else { throw ExportFailure.unavailable }
        let input = statsInput(request, snapshot: s, tasks: tasks, habits: habits)
        let stats = try StatsSnapshot.make(input)
        let coverage: String
        if let since = input.historyStartedAt, since < stats.range.end && since <= s.capturedAt {
            coverage = since <= stats.range.start ? "tracked" : "partial"
        } else { coverage = "unavailable" }
        let since = input.historyStartedAt.map { timestamp($0, zone: "UTC") } ?? ""
        let previous = StatsSnapshot.comparisonRange(query: input.query, range: stats.range, now: s.capturedAt, calendar: calendar)
        var reports: [ExportReport] = []
        let metadata: [(String, String)] = [
            ("export_version", "1"), ("captured_at", timestamp(s.capturedAt, zone: "UTC")),
            ("from_inclusive", start), ("through_inclusive", end), ("reporting_timezone", calendar.timeZone.identifier),
            ("project_id", request.projectID ?? "all"), ("project_name", request.projectID.flatMap { projects[$0]?.name } ?? "All projects"),
            ("task_keys", request.taskKeys.map { $0.sorted().joined(separator: " | ") } ?? "all"),
            ("time_units", "seconds; habit targets use their stated units; rates are fractions 0 to 1"),
            ("task_scope", "all tasks; date scope only; projected habit rows excluded"),
            ("habit_scope", "all habits; date scope only"),
            ("adjusted_totals_scope", "project and date scope only; independent of task filters; differences from recorded focus are not known manual adjustments"),
            ("weekly_targets_scope", "current week; all tasks; independent of export range and filters"),
            ("comparison_from", StatsSnapshot.dayID(previous.range.start, calendar: calendar)),
            ("comparison_through", StatsSnapshot.dayID(previous.range.endDay(calendar: calendar), calendar: calendar)),
            ("comparison_cutoff", previous.wallCutoff == nil ? "full preceding equivalent range" : "same local wall time on last comparison day"),
            ("buckets", "custom date range: daily up to 31 days, weekly up to 180 days, monthly beyond 180 days"),
            ("civil_attribution", "saved session civil day and timezone; never rebucketed into reporting timezone"),
            ("formula_protection", "user text starting with = + - @ (including leading whitespace) or tab/CR/LF is prefixed with an apostrophe"),
            ("recovery", "reporting only; use .keepbackup for recovery")
        ]
        reports.append(try report("metadata.csv", ["key", "value"], metadata.map { [.text($0.0), .text($0.1)] }))
        reports.append(try report("summary.csv", ["recorded_focus_seconds", "active_days", "daily_average_seconds", "previous_focus_seconds", "comparison_difference_seconds", "current_focus_streak_days", "best_focus_streak_days", "tracked_pomodoros", "pomodoro_coverage_start", "pomodoro_coverage", "adjusted_timesheet_seconds", "tasks_total", "tasks_completed", "task_scope", "habit_scope"], [[
            .number(stats.total), .integer(stats.activeDays), .number(stats.average), .number(stats.previousTotal), .number(stats.total - stats.previousTotal),
            .integer(stats.currentStreak), .integer(stats.bestStreak), .value(coverage == "unavailable" ? "" : String(stats.pomodoros)), .value(since), .value(coverage),
            .number(stats.adjustedTotal), .integer(stats.tasksTotal), .integer(stats.tasksCompleted), .value("all tasks; date scope only"), .value("all habits; date scope only")
        ]]))
        let days = try dayIDs(from: request.from, through: request.through, calendar: calendar)
        reports.append(try report("focus_daily.csv", ["civil_day", "recorded_focus_seconds"], days.map { [.value($0), .number(stats.dailyFocus[$0, default: 0])] }))
        reports.append(try report("focus_buckets.csv", ["bucket_id", "bucket_start", "recorded_focus_seconds"], stats.buckets.map { [.value($0.id), .value(StatsSnapshot.dayID($0.date, calendar: calendar)), .number($0.seconds)] }))
        reports.append(try report("distribution.csv", ["project_id", "project_name", "project_deleted", "task_key", "task_name", "recorded_focus_seconds"], stats.distribution.sorted { $0.id < $1.id }.map {
            projectFields($0.projectID, fallback: $0.name) + [.text($0.taskKey ?? ""), .text($0.taskKey == nil ? "" : $0.name), .number($0.seconds)]
        }))
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        reports.append(try report("focus_weekdays.csv", ["weekday", "recorded_focus_seconds"], stats.weekdays.enumerated().map { [.value(weekdays[$0.offset]), .number($0.element)] }))
        reports.append(try report("focus_hours.csv", ["recorded_local_hour", "recorded_focus_seconds"], stats.hours.enumerated().map { [.integer($0.offset), .number($0.element)] }))
        reports.append(try report("adjusted_totals.csv", adjustedHeaders, adjustedRows))
        reports.append(try report("tasks.csv", ["civil_day", "saved_tasks", "completed_tasks", "scope"], days.map { day in
            let rows = tasks.days[day, default: []].filter { $0.habitID == nil }
            return [.value(day), .integer(rows.count), .integer(rows.filter(\.isComplete).count), .value("all tasks; date scope only")]
        }))
        reports.append(try report("habits.csv", ["habit_id", "habit_name", "scheduled_opportunities", "completions", "completion_rate", "current_streak", "best_streak", "scope"], stats.habits.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [.text($0.id.uuidString), .text($0.name), .integer($0.due), .integer($0.completed), .number($0.due == 0 ? 0 : Double($0.completed) / Double($0.due)), .integer($0.currentStreak), .integer($0.bestStreak), .value("all habits; date scope only")]
        }))
        reports.append(try report("weekly_targets.csv", ["kind", "id", "name", "week_from", "week_through", "goal", "minimum", "progress", "unit", "scope"], weeklyTargets(s, stats: stats, habits: habits)))
        return reports
    }

    static func statsInput(_ request: ExportRequest, snapshot s: PersistentSnapshot, tasks: TaskArchive, habits: HabitArchive) -> StatsInput {
        let progress = Dictionary(grouping: habits.logs, by: \.habitID)
        return StatsInput(query: request.query(), now: s.capturedAt, calendar: s.calendar, projects: s.projects,
            sessions: s.workspace.sessions.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, start: $0.start, end: $0.end, timeZoneID: $0.timeZoneID) },
            completions: s.workspace.completedPomodoros.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, date: $0.completedAt) },
            historyStartedAt: s.workspace.pomodoroHistoryStartedAt,
            entries: s.workspace.entries.map { .init(projectID: $0.project.id, dayID: $0.dayID, seconds: $0.seconds) },
            tasks: tasks.days.map { day, rows in
                let ordinary = rows.filter { $0.habitID == nil }
                return .init(dayID: day, total: ordinary.count, completed: ordinary.filter(\.isComplete).count)
            }, habits: habits.habits.map { habit in
                .init(id: habit.id, name: habit.name, icon: habit.icon.rawValue, start: habit.startDay, end: habit.endDay,
                      weekdays: Set(habit.weekdays.map(\.rawValue)), target: habit.goal.target,
                      progress: Dictionary(uniqueKeysWithValues: progress[habit.id, default: []].map { ($0.dayID, $0.amount) }))
            })
    }

    private static func weeklyTargets(_ s: PersistentSnapshot, stats: StatsSnapshot, habits: HabitArchive) -> [[CSVField]] {
        let week = StatsQuery().range(now: s.capturedAt, calendar: s.calendar)
        let start = StatsSnapshot.dayID(week.start, calendar: s.calendar)
        let end = StatsSnapshot.dayID(week.endDay(calendar: s.calendar), calendar: s.calendar)
        let today = StatsSnapshot.dayID(s.capturedAt, calendar: s.calendar)
        func row(_ kind: String, _ id: String, _ name: String, _ goal: Double, _ minimum: Double?, _ progress: Double, _ unit: String) -> [CSVField] {
            [.value(kind), .text(id), .text(name), .value(start), .value(end), .number(goal), .value(minimum.map { String($0) } ?? ""), .number(progress), .value(unit), .value("current week; all tasks; independent of export range and filters")]
        }
        var rows: [[CSVField]] = []
        if let goal = s.settings?.weeklyFocusGoalMinutes { rows.append(row("global", "all", "All projects", Double(goal * 60), nil, stats.weeklyGoalSeconds, "seconds")) }
        var progress: [String: Double] = [:]
        for session in s.workspace.sessions where session.dayID >= start && session.dayID <= today {
            progress[session.project.id, default: 0] += max(0, min(session.end, s.capturedAt).timeIntervalSince(session.start))
        }
        for project in s.projects.sorted(by: { $0.id < $1.id }) where !project.deleted {
            if let target = s.workspace.projectTargets[project.id] {
                rows.append(row("project", project.id, project.name, Double(target.goal * 60), Double(target.minimum * 60), progress[project.id, default: 0], "seconds"))
            }
        }
        for habit in habits.habits.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if let target = habit.weeklyTargets {
                // Matches HabitStore.weeklyAmount: retains recorded amounts when a schedule is edited.
                let amount = habits.logs.filter { $0.habitID == habit.id && $0.dayID >= start && $0.dayID <= today }.reduce(0) { $0 + $1.amount }
                rows.append(row("habit", habit.id.uuidString, habit.name, Double(target.goal), Double(target.minimum), Double(amount), habit.weeklyUnit))
            }
        }
        return rows
    }

    static func dayIDs(from: Date, through: Date, calendar: Calendar) throws -> [String] {
        var day = calendar.startOfDay(for: from), result: [String] = []
        let end = calendar.startOfDay(for: through)
        while day <= end {
            try Task.checkCancellation()
            result.append(StatsSnapshot.dayID(day, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { throw ExportFailure.invalidRequest }
            day = next
        }
        return result
    }

    static func timestamp(_ date: Date, zone: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
