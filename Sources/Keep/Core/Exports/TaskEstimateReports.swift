import Foundation

nonisolated enum TaskEstimateReports {
    struct Row {
        let key: TaskFocusKey
        let title: String
        let status: String
        let planned: Int?
        let focused: Double
        let manual: Int?
        let habitProgress: Double?
    }

    static func make(filename: String, from: String, through: String, snapshot: PersistentSnapshot) throws -> ExportReport {
        guard let tasks = snapshot.tasks, let habits = snapshot.habits else { throw ExportFailure.unavailable }
        let totals = TaskTimeTotals(sessions: snapshot.workspace.sessions)
        let today = TaskDay.id(for: snapshot.capturedAt, calendar: snapshot.calendar)
        var rows: [TaskFocusKey: Row] = [:]
        for (day, tasks) in tasks.days where day >= from && day <= through {
            for task in tasks {
                let key = TaskFocusKey(kind: .task, id: task.id, dayID: day)
                rows[key] = Row(key: key, title: task.title, status: task.isComplete ? "complete" : "incomplete",
                    planned: task.estimateMinutes, focused: day > today ? 0 : totals.seconds[key, default: 0], manual: nil, habitProgress: nil)
            }
        }
        guard let firstDay = TaskDay.date(for: from, calendar: snapshot.calendar),
              let lastDay = TaskDay.date(for: through, calendar: snapshot.calendar) else { throw ExportFailure.invalidRequest }
        let dates = try ExportReports.dayIDs(from: firstDay, through: lastDay, calendar: snapshot.calendar)
        for habit in habits.habits where habit.goal.minuteTarget != nil {
            for day in dates where habit.isScheduled(on: day) && !tasks.hiddenHabitIDs[day, default: []].contains(habit.id) {
                let key = TaskFocusKey(kind: .habit, id: habit.id, dayID: day)
                let focused = day > today ? 0 : totals.seconds[key, default: 0]
                let manual = day > today ? 0 : habits.logs.first { $0.habitID == habit.id && $0.dayID == day }?.amount ?? 0
                let progress = Double(manual) + focused / 60
                rows[key] = Row(key: key, title: habit.name, status: progress >= Double(habit.goal.target) ? "complete" : "incomplete",
                    planned: habit.goal.target, focused: focused, manual: manual, habitProgress: progress)
            }
        }
        // Deleted list entries retain their attributed time, without inventing a saved estimate.
        for session in snapshot.workspace.sessions.sorted(by: { $0.end < $1.end }) {
            guard let reference = session.taskReference else { continue }
            let key = reference.occurrence(on: session.dayID)
            guard key.dayID >= from && key.dayID <= through, rows[key] == nil || rows[key]?.status == "removed" else { continue }
            if key.kind == .habit, let habit = habits.habits.first(where: { $0.id == key.id }), habit.goal.minuteTarget == nil { continue }
            rows[key] = Row(key: key, title: session.task, status: "removed", planned: nil,
                focused: key.dayID > today ? 0 : totals.seconds[key, default: 0], manual: nil, habitProgress: nil)
        }
        func minutes(_ value: Double) -> CSVField { .value(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)) }
        let values: [[CSVField]] = rows.values.sorted {
            if $0.key.dayID != $1.key.dayID { return $0.key.dayID < $1.key.dayID }
            if $0.key.kind != $1.key.kind { return $0.key.kind.rawValue < $1.key.kind.rawValue }
            return $0.key.id.uuidString < $1.key.id.uuidString
        }.map { row in
            [.value(row.key.dayID), .text(row.key.id.uuidString), .text(row.title), .value(row.status),
             .value(row.planned.map(String.init) ?? ""), minutes(row.focused / 60),
             row.planned.map { minutes(row.focused / 60 - Double($0)) } ?? .value(""),
             .value(row.key.kind.rawValue), .value(row.manual.map(String.init) ?? ""), row.habitProgress.map(minutes) ?? .value("")]
        }
        let data = try CSVReport.encode(headers: ["date", "task_id", "title", "completion_status", "planned_minutes", "focused_minutes", "difference_minutes", "kind", "manual_minutes", "habit_progress_minutes"], rows: values)
        return ExportReport(filename: filename, contents: data)
    }
}
