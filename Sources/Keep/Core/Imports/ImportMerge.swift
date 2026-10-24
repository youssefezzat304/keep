import Foundation

nonisolated enum ImportScope: Equatable, Sendable {
    case all
    case dates(from: String, through: String)
    func contains(_ day: String) -> Bool {
        switch self { case .all: true; case .dates(let from, let through): day >= from && day <= through }
    }
    var isAll: Bool { if case .all = self { true } else { false } }
    func validate() throws {
        if case .dates(let from, let through) = self {
            guard TaskDay.isValid(from), TaskDay.isValid(through), from <= through else { throw ImportFailure.invalidRange }
        }
    }
}

nonisolated enum ImportResolution: String, CaseIterable, Sendable {
    case local = "Keep local", incoming = "Use imported", both = "Keep both", link = "Link to existing"
}

nonisolated struct ImportDecisions: Equatable, Sendable {
    var resolutions: [String: ImportResolution] = [:]
    var names: [String: String] = [:]
}

nonisolated struct ImportIssue: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let choices: [ImportResolution]
    let requiresChoice: Bool
    var needsName = false
}

nonisolated struct ImportChange: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case addition = "Add", identical = "Unchanged", replacement = "Replace" }
    let id: String
    let category: String
    let detail: String
    let kind: Kind
}

nonisolated struct ImportReview: Equatable, Sendable {
    let candidate: KeepDataPayload
    let changes: [ImportChange]
    let issues: [ImportIssue]
    let blockers: [String]
    let supportingRecords: Int
    let hasChanges: Bool
    var replacements: Int { changes.filter { $0.kind == .replacement }.count }
    var additions: Int { changes.filter { $0.kind == .addition }.count }
    var identical: Int { changes.filter { $0.kind == .identical }.count }
    var canApply: Bool { hasChanges && blockers.isEmpty }
}

/// Pure, deterministic merging. Nothing here reads stores or writes persistent archives.
nonisolated enum ImportMerge {
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func review(source: KeepDataPayload, local: KeepDataPayload, scope: ImportScope, decisions: ImportDecisions = .init()) throws -> ImportReview {
        try scope.validate(); try source.validate(); try local.validate()
        var engine = Engine(source: source, local: local, scope: scope, decisions: decisions)
        return try engine.run()
    }

    private struct Engine {
        let source: KeepDataPayload
        let local: KeepDataPayload
        let scope: ImportScope
        let decisions: ImportDecisions
        var changes: [ImportChange] = []
        var issues: [ImportIssue] = []
        var blockers: [String] = []
        var supporting = 0

        mutating func changed(_ id: String, _ category: String, _ detail: String, _ kind: ImportChange.Kind) {
            changes.append(.init(id: id, category: category, detail: detail, kind: kind))
        }
        mutating func choose(_ id: String, title: String, detail: String, choices: [ImportResolution] = [.local, .incoming], required: Bool = false, needsName: Bool = false) -> ImportResolution {
            issues.append(.init(id: id, title: title, detail: detail, choices: choices, requiresChoice: required, needsName: needsName))
            if required && decisions.resolutions[id] == nil { blockers.append("Choose how to resolve \(title).") }
            let selected = decisions.resolutions[id] ?? (required ? .local : .incoming)
            return choices.contains(selected) ? selected : .local
        }
        mutating func merge<T: Equatable>(_ incoming: [T], into values: inout [T], key: (T) -> String, category: String, label: (T) -> String, allowed: (T) -> Bool = { _ in true }) {
            var indexes = Dictionary(values.enumerated().map { (key($0.element), $0.offset) }, uniquingKeysWith: { first, _ in first })
            for value in incoming {
                let id = category + "/" + key(value)
                if let index = indexes[key(value)] {
                    if values[index] == value { changed(id, category, label(value), .identical) }
                    else {
                        let withinScope = allowed(values[index])
                        let detail = withinScope ? "Existing: \(label(values[index]))\nImported: \(label(value))" : "The existing record is outside your selected dates. Keep local or expand the date range."
                        let choice = choose(id, title: "\(category): \(label(value))", detail: detail, choices: withinScope ? [.local, .incoming] : [.local], required: !withinScope)
                        if choice == .incoming { values[index] = value; changed(id, category, detail, .replacement) }
                    }
                } else { indexes[key(value)] = values.count; values.append(value); changed(id, category, label(value), .addition) }
            }
        }

        mutating func run() throws -> ImportReview {
            let selectedScope = scope
            var result = local
            var imported = source
            let original = local
            imported.workspace.sessions = source.workspace.sessions.filter { scope.contains($0.dayID) }
            imported.workspace.entries = source.workspace.entries.filter { scope.contains($0.dayID) }
            imported.workspace.completedPomodoros = source.workspace.completedPomodoros.filter { scope.contains($0.dayID) }
            var reportingCalendar = Calendar(identifier: .gregorian)
            reportingCalendar.timeZone = TimeZone(identifier: source.reportingTimeZone) ?? .gmt
            var localReportingCalendar = Calendar(identifier: .gregorian)
            localReportingCalendar.timeZone = TimeZone(identifier: local.reportingTimeZone) ?? .gmt
            imported.workspace.taskActivities = source.workspace.taskActivities.filter { scope.contains(TaskDay.id(for: $0.lastUsed, calendar: reportingCalendar)) }
            imported.tasks.days = source.tasks.days.filter { scope.contains($0.key) }
            imported.tasks.hiddenHabitIDs = source.tasks.hiddenHabitIDs.filter { scope.contains($0.key) }
            imported.habits.logs = source.habits.logs.filter { scope.contains($0.dayID) }
            imported.habits.consumedTimerGoals = source.habits.consumedTimerGoals?.mapValues { Set($0.filter(scope.contains)) }
            if case .dates(let from, let through) = scope {
                let referenced = Set(imported.workspace.sessions.compactMap { session -> UUID? in
                    if case .habit(let id) = session.taskReference { return id }; return nil
                } + imported.workspace.taskActivities.compactMap { activity -> UUID? in
                    if case .habit(let id) = activity.taskReference { return id }; return nil
                } + imported.habits.logs.map(\.habitID) + imported.tasks.hiddenHabitIDs.values.flatMap { $0 })
                imported.habits.habits = source.habits.habits.filter { habit in
                    (habit.startDay <= through && (habit.endDay ?? "9999-12-31") >= from) || referenced.contains(habit.id)
                }
                for reference in imported.workspace.sessions.compactMap(\.taskReference) + imported.workspace.taskActivities.compactMap(\.taskReference) {
                    if case .task(let id, let day) = reference, !scope.contains(day),
                       !(result.tasks.days[day] ?? []).contains(where: { $0.id == id }),
                       let task = source.tasks.days[day]?.first(where: { $0.id == id }),
                       !(imported.tasks.days[day] ?? []).contains(where: { $0.id == id }) {
                        imported.tasks.days[day, default: []].append(task); supporting += 1
                    }
                }
            }

            let relevantProjects = Set(imported.workspace.entries.map { $0.project.id } + imported.workspace.sessions.map { $0.project.id } + imported.workspace.completedPomodoros.map { $0.project.id } + imported.workspace.taskActivities.map { $0.project.id })
            let projectDefinitions = source.workspace.projects.filter { scope.isAll || relevantProjects.contains($0.id) }
            var projectMap: [String: FocusProject] = [:]
            let visibleProjects = TimesheetLedger(tracked: result.workspace).catalogProjects
            let visibleIDs = Set(visibleProjects.map(\.id))
            var occupiedProjects = visibleProjects + result.workspace.projects.filter { !visibleIDs.contains($0.id) }
            for definition in projectDefinitions {
                var value = definition
                if !occupiedProjects.contains(where: { $0.id == value.id }),
                   let match = occupiedProjects.first(where: { nameKey($0.name) == nameKey(value.name) && !result.workspace.deletedProjectIDs.contains($0.id) }) {
                    let id = "name/project/" + value.id
                    let choice = choose(id, title: "Project ‘\(value.name)’ matches ‘\(match.name)’", detail: "These projects have different IDs. Linking also links their history and goals.", choices: [.link, .both], required: true, needsName: true)
                    if choice == .both {
                        let name = (decisions.names[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if name.isEmpty || name.count > 80 || occupiedProjects.contains(where: { nameKey($0.name) == nameKey(name) }) { blockers.append("Enter a unique name for project ‘\(value.name)’.") }
                        else { value = FocusProject(id: value.id, name: name, accent: value.accent, category: value.category, hourlyRate: value.hourlyRate) }
                    } else { value = FocusProject(id: match.id, name: match.name, accent: value.accent, category: value.category, hourlyRate: value.hourlyRate) }
                }
                projectMap[definition.id] = value
                if !occupiedProjects.contains(where: { $0.id == value.id }) { occupiedProjects.append(value) }
            }
            var habitMap: [UUID: UUID] = [:]
            var occupiedHabits = result.habits.habits
            for definition in imported.habits.habits {
                var value = definition
                if !occupiedHabits.contains(where: { $0.id == value.id }), let match = occupiedHabits.first(where: { nameKey($0.name) == nameKey(value.name) }) {
                    let id = "name/habit/" + value.id.uuidString
                    let choice = choose(id, title: "Habit ‘\(value.name)’ matches ‘\(match.name)’", detail: "These habits have different IDs. Linking also links check-ins, timed progress and goals.", choices: [.link, .both], required: true, needsName: true)
                    if choice == .both {
                        let name = (decisions.names[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if name.isEmpty || name.count > 80 || occupiedHabits.contains(where: { nameKey($0.name) == nameKey(name) }) { blockers.append("Enter a unique name for habit ‘\(value.name)’.") }
                        else { value = Habit(id: value.id, name: name, icon: value.icon, startDay: value.startDay, endDay: value.endDay, goal: value.goal, weekdays: value.weekdays, weeklyTargets: value.weeklyTargets) }
                    } else { value = Habit(id: match.id, name: match.name, icon: value.icon, startDay: value.startDay, endDay: value.endDay, goal: value.goal, weekdays: value.weekdays, weeklyTargets: value.weeklyTargets) }
                }
                habitMap[definition.id] = value.id
                merge([value], into: &result.habits.habits, key: { $0.id.uuidString }, category: "Habits", label: { "\($0.name) · \($0.goal.summary) · \($0.startDay)–\($0.endDay ?? "ongoing") · days \($0.weekdays.map { $0.title(calendar: reportingCalendar) }.joined(separator: ", ")) · weekly \($0.weeklyTargets.map { "goal \($0.goal), minimum \($0.minimum)" } ?? "none") · icon \($0.icon.title)" })
                if !occupiedHabits.contains(where: { $0.id == value.id }) { occupiedHabits.append(value) }
            }
            supporting += projectDefinitions.count + imported.habits.habits.count
            func project(_ value: FocusProject) -> FocusProject { projectMap[value.id] ?? value }
            func reference(_ value: TaskReference?) -> TaskReference? {
                if case .habit(let id) = value { return .habit(id: habitMap[id] ?? id) }; return value
            }
            // A linked custom project takes precedence over its unused built-in source
            // definition. Otherwise one source could contradict itself after remapping.
            let foreignTargets = Set(projectMap.filter { $0.key != $0.value.id }.map { $0.value.id })
            let foreignCounts = Dictionary(grouping: projectMap.filter { $0.key != $0.value.id }, by: { $0.value.id })
            if foreignCounts.values.contains(where: { $0.count > 1 }) {
                blockers.append("Link each imported project to a different project, or keep both with unique names.")
            }
            for definition in projectDefinitions {
                guard let value = projectMap[definition.id], !(definition.id == value.id && foreignTargets.contains(value.id)) else { continue }
                var definitions = result.workspace.projects
                merge([value], into: &definitions, key: \.id, category: "Projects", label: { "\($0.name) · \($0.accent.name) · \($0.hourlyRate.map { "\($0.currency) \($0.amount)/hour" } ?? "no hourly rate")" })
                let builtIn = FocusProject.defaults.contains { $0.id == value.id }
                if let chosen = definitions.first(where: { $0.id == value.id }) {
                    if builtIn {
                        result.workspace.projectOverrides.removeAll { $0.id == value.id }
                        if chosen != FocusProject.defaults.first(where: { $0.id == value.id }) { result.workspace.projectOverrides.append(chosen) }
                    } else {
                        result.workspace.customProjects.removeAll { $0.id == value.id }; result.workspace.customProjects.append(chosen)
                    }
                }
                let wasDeleted = result.workspace.deletedProjectIDs.contains(value.id)
                let incomingDeleted = source.workspace.deletedProjectIDs.contains(definition.id)
                if wasDeleted != incomingDeleted {
                    let id = "project-status/" + value.id
                    if choose(id, title: "Project status: \(value.name)", detail: "Existing: \(wasDeleted ? "deleted" : "active"). Imported: \(incomingDeleted ? "deleted" : "active"). This affects the project catalog beyond the selected dates.") == .incoming {
                        if incomingDeleted { result.workspace.deletedProjectIDs.insert(value.id) } else { result.workspace.deletedProjectIDs.remove(value.id) }
                        changed(id, "Project status", value.name, .replacement)
                    }
                }
                let goal = source.workspace.projectTargets[definition.id]
                if goal != result.workspace.projectTargets[value.id] {
                    let id = "project-goal/" + value.id
                    if choose(id, title: "Project goal: \(value.name)", detail: "Existing: \(target(result.workspace.projectTargets[value.id])). Imported: \(target(goal)). Goals apply beyond the selected dates.") == .incoming {
                        result.workspace.projectTargets[value.id] = goal
                        changed(id, "Goals", value.name + " · " + target(goal), original.workspace.projectTargets[value.id] == nil ? .addition : .replacement)
                    }
                }
            }
            imported.workspace.sessions = imported.workspace.sessions.map {
                var value = $0; value.project = project(value.project); value.taskReference = reference(value.taskReference); return value
            }
            imported.workspace.completedPomodoros = imported.workspace.completedPomodoros.map {
                .init(id: $0.id, project: project($0.project), task: $0.task, completedAt: $0.completedAt, dayID: $0.dayID, timeZoneID: $0.timeZoneID, focusDuration: $0.focusDuration)
            }
            imported.workspace.taskActivities = imported.workspace.taskActivities.map {
                var value = $0; value.project = project(value.project); value.taskReference = reference(value.taskReference); return value
            }

            // Resolve cross-file overlaps as connected groups, not order-dependent pairs.
            let knownSessions = Dictionary(uniqueKeysWithValues: result.workspace.sessions.map { ($0.id, $0) })
            let changedSpans = imported.workspace.sessions.filter { session in
                guard let existing = knownSessions[session.id] else { return true }
                return existing.start != session.start || existing.end != session.end
            }
            let changedSpanIDs = Set(changedSpans.map(\.id))
            let groups = try overlapGroups(local: result.workspace.sessions, incoming: changedSpans)
            var rejectedIncoming = Set<String>(), removedLocal = Set<String>()
            for group in groups {
                let id = "overlap/" + group.incoming.map(\.id).sorted().joined(separator: "|") + "/" + group.local.map(\.id).sorted().joined(separator: "|")
                let outside = group.local.contains { !scope.contains($0.dayID) }
                let detail = "Local:\n" + group.local.map(sessionLabel).joined(separator: "\n") + "\nImported:\n" + group.incoming.map(sessionLabel).joined(separator: "\n") + (outside ? "\nSome local records are outside the selected dates. Keep local or expand the range." : "\nUse imported removes the local sessions listed above. Keep both counts both sets of time.")
                let choice = choose(id, title: "Overlapping sessions", detail: detail, choices: outside ? [.local] : [.local, .incoming, .both], required: true)
                if choice == .local { rejectedIncoming.formUnion(group.incoming.map(\.id)) }
                if choice == .incoming {
                    removedLocal.formUnion(group.local.map(\.id))
                    for session in group.local { changed("removed/" + session.id, "Sessions", "Remove local: " + sessionLabel(session), .replacement) }
                }
            }
            result.workspace.sessions.removeAll { removedLocal.contains($0.id) }
            let incomingSessions = imported.workspace.sessions.filter {
                !rejectedIncoming.contains($0.id) && (!removedLocal.contains($0.id) || changedSpanIDs.contains($0.id))
            }
            merge(incomingSessions, into: &result.workspace.sessions, key: \.id, category: "Sessions", label: sessionLabel, allowed: { selectedScope.contains($0.dayID) })
            merge(imported.workspace.completedPomodoros, into: &result.workspace.completedPomodoros, key: { $0.id.uuidString }, category: "Pomodoros", label: { "\($0.dayID) · \($0.project.name) · \($0.task) · \($0.focusDuration)" }, allowed: { selectedScope.contains($0.dayID) })
            if scope.isAll, let since = source.workspace.pomodoroHistoryStartedAt {
                result.workspace.pomodoroHistoryStartedAt = min(result.workspace.pomodoroHistoryStartedAt ?? since, since)
                if result.workspace.pomodoroHistoryStartedAt != original.workspace.pomodoroHistoryStartedAt {
                    changed("coverage", "History coverage", "Pomodoro tracking began \(since.formatted())", original.workspace.pomodoroHistoryStartedAt == nil ? .addition : .replacement)
                }
            } else if !result.workspace.completedPomodoros.isEmpty && result.workspace.pomodoroHistoryStartedAt == nil {
                result.workspace.pomodoroHistoryStartedAt = result.workspace.completedPomodoros.map(\.completedAt).min()
            }

            // Merge signed adjustments independently of sessions. Importing session time
            // and its aggregate must never add that same time twice.
            let originalRecorded = recorded(original.workspace.sessions)
            let sourceRecorded = recorded(source.workspace.sessions)
            let finalRecorded = recorded(result.workspace.sessions)
            var adjustments = Dictionary(uniqueKeysWithValues: original.workspace.entries.map { ($0.id, $0.seconds - originalRecorded[$0.id, default: 0]) })
            var cells = Dictionary(uniqueKeysWithValues: original.workspace.entries.map { ($0.id, $0) })
            var incomingAdjustments: [String: Double] = [:]
            for entry in imported.workspace.entries {
                var mapped = entry; mapped.project = project(entry.project)
                incomingAdjustments[mapped.id, default: 0] += entry.seconds - sourceRecorded[entry.id, default: 0]
                if cells[mapped.id] == nil { cells[mapped.id] = mapped }
            }
            for key in incomingAdjustments.keys.sorted() {
                guard let incoming = incomingAdjustments[key], let cell = cells[key] else { continue }
                if let previous = adjustments[key] {
                    if abs(previous - incoming) > 0.000001 {
                        let id = "adjustment/" + key
                        if choose(id, title: "Time correction: \(cell.dayID) · \(cell.project.name)", detail: "Existing adjustment: \(previous) seconds. Imported adjustment: \(incoming) seconds. Recorded sessions are merged separately.") == .incoming {
                            adjustments[key] = incoming; changed(id, "Time corrections", "\(cell.dayID) · \(cell.project.name) · \(incoming) seconds", .replacement)
                        }
                    } else { changed("adjustment/" + key, "Time corrections", "\(cell.dayID) · \(cell.project.name)", .identical) }
                } else { adjustments[key] = incoming; changed("adjustment/" + key, "Time corrections", "\(cell.dayID) · \(cell.project.name) · \(incoming) seconds", .addition) }
            }
            for session in result.workspace.sessions where cells[session.project.id + "/" + session.dayID] == nil {
                let cell = TimesheetEntry(project: session.project, dayID: session.dayID, seconds: 0); cells[cell.id] = cell
            }
            result.workspace.entries = cells.values.map { cell in
                var value = cell; value.seconds = max(0, finalRecorded[cell.id, default: 0] + adjustments[cell.id, default: 0]); return value
            }.sorted { $0.id < $1.id }

            for day in imported.tasks.days.keys.sorted() {
                var values = result.tasks.days[day, default: []]
                merge(imported.tasks.days[day, default: []], into: &values, key: { day + "/" + $0.id.uuidString }, category: "Tasks", label: { "\(day) · \($0.title) · \($0.isComplete ? "complete" : "incomplete") · \($0.estimateMinutes.map { "\($0) min" } ?? "no estimate")" })
                result.tasks.days[day] = values
            }
            let habitNames = Dictionary(uniqueKeysWithValues: result.habits.habits.map { ($0.id, $0.name) })
            let remappedLogs = imported.habits.logs.map { HabitLog(habitID: habitMap[$0.habitID] ?? $0.habitID, dayID: $0.dayID, amount: $0.amount) }
            merge(remappedLogs, into: &result.habits.logs, key: { $0.habitID.uuidString + "/" + $0.dayID }, category: "Habit check-ins", label: { log in "\(log.dayID) · \(habitNames[log.habitID] ?? log.habitID.uuidString) · \(log.amount)" })
            for (day, ids) in imported.tasks.hiddenHabitIDs {
                let mapped = Set(ids.map { habitMap[$0] ?? $0 })
                let added = mapped.subtracting(result.tasks.hiddenHabitIDs[day, default: []])
                result.tasks.hiddenHabitIDs[day, default: []].formUnion(mapped)
                if !added.isEmpty { changed("hidden/" + day, "Hidden habit rows", "\(day) · \(added.count) rows", .addition) }
            }
            var consumed = result.habits.consumedTimerGoals ?? [:]
            for (id, days) in imported.habits.consumedTimerGoals ?? [:] { consumed[habitMap[id] ?? id, default: []].formUnion(days) }
            result.habits.consumedTimerGoals = consumed.isEmpty ? nil : consumed
            let existingActivities = Dictionary(uniqueKeysWithValues: result.workspace.taskActivities.map { (activityKey($0), $0.id) })
            let activities = imported.workspace.taskActivities.map { value in
                TaskActivity(id: existingActivities[activityKey(value)] ?? value.id, title: value.title, project: value.project,
                    lastUsed: value.lastUsed, isPinned: value.isPinned, taskReference: value.taskReference, habitNameExtension: value.habitNameExtension)
            }
            merge(activities, into: &result.workspace.taskActivities, key: { $0.id.uuidString }, category: "Suggestions", label: { "\($0.project.name) · \($0.title) · \($0.isPinned ? "pinned" : "unpinned") · \($0.lastUsed.formatted())" }, allowed: { selectedScope.contains(TaskDay.id(for: $0.lastUsed, calendar: localReportingCalendar)) })
            if source.weeklyFocusGoalMinutes != result.weeklyFocusGoalMinutes {
                let id = "global-goal"
                if choose(id, title: "Overall weekly goal", detail: "Existing: \(result.weeklyFocusGoalMinutes.map(String.init) ?? "none") minutes. Imported: \(source.weeklyFocusGoalMinutes.map(String.init) ?? "none") minutes. This goal applies beyond the selected dates.") == .incoming {
                    result.weeklyFocusGoalMinutes = source.weeklyFocusGoalMinutes
                    changed(id, "Goals", "Overall weekly goal", original.weeklyFocusGoalMinutes == nil ? .addition : .replacement)
                }
            }
            if scope.isAll { merge(source.channels, into: &result.channels, key: \.id, category: "Saved channels", label: { "\($0.name) · \($0.url.absoluteString)" }) }

            // Imported history is silent, including the next live tick after installation.
            let effective = result.habits.effectiveProgress(recorded: TaskTimeTotals(sessions: result.workspace.sessions).habits)
            let effectiveLogs = Dictionary(grouping: effective.logs, by: \.habitID)
            for habit in result.habits.habits where habit.goal.minuteTarget != nil {
                for log in effectiveLogs[habit.id, default: []] where log.amount >= habit.goal.target && habit.isScheduled(on: log.dayID) {
                    consumed[habit.id, default: []].insert(log.dayID)
                }
            }
            result.habits.consumedTimerGoals = consumed.isEmpty ? nil : consumed
            if result.habits.consumedTimerGoals != original.habits.consumedTimerGoals {
                changed("completion-markers", "Habit tracking markers", "Historical habit completions stay silent", .addition)
            }

            // Definition edits update display metadata consistently with normal project edits.
            let metadata = Dictionary(uniqueKeysWithValues: result.workspace.projects.map { ($0.id, $0) })
            result.workspace.entries = result.workspace.entries.map { var value = $0; value.project = metadata[value.project.id] ?? value.project; return value }
            result.workspace.sessions = result.workspace.sessions.map { var value = $0; value.project = metadata[value.project.id] ?? value.project; return value }
            result.workspace.taskActivities = result.workspace.taskActivities.map { var value = $0; value.project = metadata[value.project.id] ?? value.project; return value }
            var normalized = TimesheetLedger(tracked: result.workspace)
            normalized.normalizeProjectCatalog()
            let normalizedData = TrackedWorkspace(normalized)
            if normalizedData != result.workspace {
                result.workspace = normalizedData
                changed("project-colors", "Project colors", "Reserve Habits’ color and assign available colors to imported projects", .addition)
            }
            let projectCount = normalized.catalogProjects.filter { !normalized.deletedProjectIDs.contains($0.id) }.count - 1
            let localCount = TimesheetLedger(tracked: original.workspace).catalogProjects.filter { !original.workspace.deletedProjectIDs.contains($0.id) }.count - 1
            if projectCount > max(30, localCount) { blockers.append("This import exceeds the 30-project limit. Delete unused projects or import fewer projects.") }
            // Never manufacture continuity for a partial import; retain the local marker.
            result.reportingTimeZone = original.reportingTimeZone
            do { try result.validate() }
            catch {
                for habit in result.habits.habits {
                    let invalid = result.habits.logs.filter { $0.habitID == habit.id && (!habit.isWithinRange($0.dayID) || (habit.goal == .checkIn && $0.amount != 1)) }
                    if !invalid.isEmpty {
                        blockers.append("Habit ‘\(habit.name)’ conflicts with saved check-ins on \(invalid.prefix(5).map(\.dayID).joined(separator: ", ")). Keep its local definition or change the selected dates.")
                    }
                }
                if blockers.isEmpty { blockers.append("The combined data is invalid. Retain local definitions or change the selected dates. Names and record identities must remain unique.") }
            }
            return ImportReview(candidate: result, changes: changes.sorted { $0.id < $1.id }, issues: Dictionary(issues.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }).values.sorted { $0.id < $1.id }, blockers: blockers, supportingRecords: supporting, hasChanges: !equivalent(result, original))
        }

        func target(_ value: WeeklyTargets?) -> String { value.map { "goal \($0.goal), minimum \($0.minimum)" } ?? "none" }
    }

    static func activityKey(_ activity: TaskActivity) -> String { activity.project.id + "/" + (activity.taskReference?.storageKey ?? "name/" + nameKey(activity.title)) }
    static func sessionLabel(_ session: RecordedSession) -> String { "\(session.dayID) · \(session.startTime)–\(session.editableEndTime) · \(session.project.name) · \(session.task) · \(session.source.title) · \(session.timeZoneID)" }
    static func recorded(_ sessions: [RecordedSession]) -> [String: Double] {
        sessions.reduce(into: [:]) { $0[$1.project.id + "/" + $1.dayID, default: 0] += $1.seconds }
    }
    static func equivalent(_ lhs: KeepDataPayload, _ rhs: KeepDataPayload) -> Bool {
        func ordered(_ source: KeepDataPayload) -> KeepDataPayload {
            var value = source
            value.workspace.entries.sort { $0.id < $1.id }; value.workspace.sessions.sort { $0.id < $1.id }
            value.workspace.customProjects.sort { $0.id < $1.id }; value.workspace.projectOverrides.sort { $0.id < $1.id }
            value.workspace.completedPomodoros.sort { $0.id.uuidString < $1.id.uuidString }; value.workspace.taskActivities.sort { $0.id.uuidString < $1.id.uuidString }
            value.habits.habits.sort { $0.id.uuidString < $1.id.uuidString }; value.habits.logs.sort { $0.habitID == $1.habitID ? $0.dayID < $1.dayID : $0.habitID.uuidString < $1.habitID.uuidString }
            value.channels.sort { $0.id < $1.id }
            value.tasks.days = value.tasks.days.filter { !$0.value.isEmpty }
            value.tasks.hiddenHabitIDs = value.tasks.hiddenHabitIDs.filter { !$0.value.isEmpty }
            let consumed = (value.habits.consumedTimerGoals ?? [:]).filter { !$0.value.isEmpty }
            value.habits.consumedTimerGoals = consumed.isEmpty ? nil : consumed
            return value
        }
        return ordered(lhs) == ordered(rhs)
    }
    private struct OverlapGroup { var local: [RecordedSession]; var incoming: [RecordedSession] }
    private static func overlapGroups(local: [RecordedSession], incoming: [RecordedSession]) throws -> [OverlapGroup] {
        let all = local.map { (session: $0, incoming: false) } + incoming.map { (session: $0, incoming: true) }
        let sorted = all.indices.sorted { all[$0].session.start < all[$1].session.start }
        // Union-find avoids retaining quadratic numbers of edges for dense overlaps.
        var parents = Array(all.indices), touched = Set<Int>(), active: [Int] = []
        func root(_ index: Int) -> Int {
            var cursor = index
            while parents[cursor] != cursor {
                parents[cursor] = parents[parents[cursor]]; cursor = parents[cursor]
            }
            return cursor
        }
        // Retimed versions of one identity belong in the same decision group as
        // their original, even when cross-file overlaps form a crossed pair.
        let localIndexes = Dictionary(uniqueKeysWithValues: local.enumerated().map { ($0.element.id, $0.offset) })
        for index in local.count..<all.count {
            if let matching = localIndexes[all[index].session.id] { parents[root(index)] = root(matching) }
        }
        for index in sorted {
            try Task.checkCancellation()
            active.removeAll { all[$0].session.end <= all[index].session.start }
            for previous in active where all[previous].incoming != all[index].incoming && all[previous].session.id != all[index].session.id {
                touched.insert(index); touched.insert(previous)
                let left = root(index), right = root(previous)
                if left != right { parents[right] = left }
            }
            active.append(index)
        }
        var groups: [Int: OverlapGroup] = [:]
        let touchedRoots = Set(touched.map(root))
        for index in all.indices where touchedRoots.contains(root(index)) {
            let key = root(index)
            if all[index].incoming { groups[key, default: .init(local: [], incoming: [])].incoming.append(all[index].session) }
            else { groups[key, default: .init(local: [], incoming: [])].local.append(all[index].session) }
        }
        return groups.keys.sorted().compactMap { key in
            guard var group = groups[key] else { return nil }
            group.local.sort { $0.id < $1.id }; group.incoming.sort { $0.id < $1.id }; return group
        }
    }
}
