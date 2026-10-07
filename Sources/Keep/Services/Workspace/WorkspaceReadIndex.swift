import Foundation
import Observation

/// A bounded mutation feed. Values are individual records, never retained ledger arrays.
nonisolated struct WorkspaceReadBatch: Sendable {
    let epoch: UUID
    let revision: UInt64
    let reset: Bool
    let updates: [WorkspaceMutation]
    let projects: [StatsInput.Project]
    let historyStartedAt: Date?
}

nonisolated struct WorkspaceMutation: Sendable {
    let revision: UInt64
    let changes: [WorkspaceChange]
}

@Observable final class WorkspaceReadIndex {
    private(set) var revision: UInt64 = 0
    private(set) var metadataRevision: UInt64 = 0
    private(set) var catalogRevision: UInt64 = 0
    @ObservationIgnored private(set) var epoch = UUID()
    @ObservationIgnored private(set) var sessions: [String: RecordedSession] = [:]
    @ObservationIgnored private(set) var entries: [String: TimesheetEntry] = [:]
    @ObservationIgnored private var completions: [UUID: CompletedPomodoro] = [:]
    @ObservationIgnored private var sessionDays: [String: Set<String>] = [:]
    @ObservationIgnored private var entryDays: [String: Set<String>] = [:]
    @ObservationIgnored private var projectReferences: [String: Int] = [:]
    @ObservationIgnored private var historicalProjects: [String: FocusProject] = [:]
    @ObservationIgnored private var sessionOrder: [String: Int] = [:]
    @ObservationIgnored private var entryOrder: [String: Int] = [:]
    @ObservationIgnored private var completionOrder: [UUID: Int] = [:]
    @ObservationIgnored private var nextOrder = 0
    @ObservationIgnored private var journal: [(revision: UInt64, changes: [WorkspaceChange])] = []
    @ObservationIgnored private var journalFloor: UInt64 = 0
    @ObservationIgnored private(set) var retainedMutationCount = 0
    @ObservationIgnored private var dayRevisions: [String: UInt64] = [:]
    @ObservationIgnored private(set) var statsProjects: [StatsInput.Project] = []
    @ObservationIgnored private(set) var activeProjects: [FocusProject] = []
    @ObservationIgnored private(set) var suggestions: [TaskActivity] = []
    @ObservationIgnored private var normalizedTasks: [String: String] = [:]
    @ObservationIgnored private var taskNames: [String: [String: String]] = [:]
    @ObservationIgnored private var activities: [UUID: TaskActivity] = [:]
    @ObservationIgnored private var activityOrder: [UUID: Int] = [:]
    @ObservationIgnored private var labels: [String: [String: TaskLabel]] = [:]
    private final class TaskLabel {
        struct Source { let id: String; let priority: Int; let order: Int; let name: String }
        var sources: [String: Source] = [:]
        var latest: Source?
        func add(_ source: Source) {
            sources[source.id] = source
            if latest == nil || source.priority > (latest?.priority ?? -1)
                || (source.priority == latest?.priority && source.order >= (latest?.order ?? -1)) { latest = source }
        }
        func remove(_ id: String) {
            sources.removeValue(forKey: id)
            if latest?.id == id {
                latest = sources.values.max { $0.priority == $1.priority ? $0.order < $1.order : $0.priority < $1.priority }
            }
        }
    }
    @ObservationIgnored private var historyStartedAt: Date?

    init(ledger: TimesheetLedger) { rebuild(ledger) }

    func rebuild(_ ledger: TimesheetLedger) {
        epoch = UUID(); journal = []; retainedMutationCount = 0; journalFloor = revision; sessions = [:]; entries = [:]; completions = [:]
        sessionDays = [:]; entryDays = [:]; projectReferences = [:]; historicalProjects = [:]
        sessionOrder = [:]; entryOrder = [:]; completionOrder = [:]; nextOrder = 0; dayRevisions = [:]; taskNames = [:]
        activities = [:]; activityOrder = [:]; labels = [:]; normalizedTasks = [:]
        let changes = ledger.entries.map(WorkspaceChange.entry) + ledger.sessions.map(WorkspaceChange.session)
            + ledger.completedPomodoros.map(WorkspaceChange.completion) + ledger.taskActivities.map(WorkspaceChange.activity) + [.catalog, .coverage]
        apply(changes, ledger: ledger)
        journal = []; retainedMutationCount = 0; journalFloor = revision
    }

    func apply(_ changes: [WorkspaceChange], ledger: TimesheetLedger) {
        guard !changes.isEmpty else { return }
        revision &+= 1
        var metadataChanged = false
        for change in changes {
            switch change {
            case .entry(let entry):
                if entries.updateValue(entry, forKey: entry.id) == nil {
                    retain(entry.project); entryDays[entry.dayID, default: []].insert(entry.id); metadataChanged = true
                    entryOrder[entry.id] = nextOrder; nextOrder += 1
                }
                dayRevisions[entry.dayID] = revision
            case .removeEntry(let entry):
                if entries.removeValue(forKey: entry.id) != nil { release(entry.project); metadataChanged = true }
                entryDays[entry.dayID]?.remove(entry.id); entryOrder.removeValue(forKey: entry.id); dayRevisions[entry.dayID] = revision
            case .session(let session):
                let old = sessions.updateValue(session, forKey: session.id)
                if old == nil {
                    retain(session.project); sessionDays[session.dayID, default: []].insert(session.id)
                    sessionOrder[session.id] = nextOrder; nextOrder += 1
                    metadataChanged = true
                    addTaskSource("s:" + session.id, title: session.task, projectID: session.project.id, priority: 0, order: sessionOrder[session.id, default: 0])
                } else if let old, old.task != session.task {
                    removeTaskSource("s:" + session.id, title: old.task, projectID: old.project.id)
                    addTaskSource("s:" + session.id, title: session.task, projectID: session.project.id, priority: 0, order: sessionOrder[session.id, default: 0])
                    metadataChanged = true
                }
                dayRevisions[session.dayID] = revision
            case .removeSession(let session):
                if sessions.removeValue(forKey: session.id) != nil { release(session.project); metadataChanged = true }
                sessionDays[session.dayID]?.remove(session.id); sessionOrder.removeValue(forKey: session.id)
                removeTaskSource("s:" + session.id, title: session.task, projectID: session.project.id)
                dayRevisions[session.dayID] = revision
            case .completion(let completion):
                if completions.updateValue(completion, forKey: completion.id) == nil {
                    retain(completion.project); completionOrder[completion.id] = nextOrder; nextOrder += 1
                }
                addTaskSource("c:" + completion.id.uuidString, title: completion.task, projectID: completion.project.id, priority: 1, order: completionOrder[completion.id, default: 0])
                metadataChanged = true
            case .activity(let activity):
                let old = activities.updateValue(activity, forKey: activity.id)
                if activityOrder[activity.id] == nil { activityOrder[activity.id] = nextOrder; nextOrder += 1 }
                if let old, old.title != activity.title { removeTaskSource("a:" + old.id.uuidString, title: old.title, projectID: old.project.id) }
                addTaskSource("a:" + activity.id.uuidString, title: activity.title, projectID: activity.project.id, priority: 2, order: activityOrder[activity.id, default: 0])
                metadataChanged = true
            case .catalog: metadataChanged = true
            case .coverage: historyStartedAt = ledger.pomodoroHistoryStartedAt
            }
        }
        if metadataChanged {
            activeProjects = (FocusProject.defaults + ledger.customProjects).filter { !ledger.deletedProjectIDs.contains($0.id) }
            var catalog = historicalProjects.filter { projectReferences[$0.key, default: 0] > 0 }
            for project in activeProjects + [.unassigned] { catalog[project.id] = project }
            let updatedProjects: [StatsInput.Project] = catalog.values.map { .init(id: $0.id, name: $0.name, accent: $0.accent.rawValue, deleted: ledger.deletedProjectIDs.contains($0.id)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if updatedProjects != statsProjects { catalogRevision &+= 1; statsProjects = updatedProjects }
            let ids = Set((activeProjects + [.unassigned]).map(\.id))
            suggestions = activities.values.filter { ids.contains($0.project.id) }.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                if $0.lastUsed != $1.lastUsed { return $0.lastUsed > $1.lastUsed }
                return $0.id.uuidString < $1.id.uuidString
            }
            metadataRevision &+= 1
        }
        journal.append((revision, changes))
        retainedMutationCount += changes.count
        while journal.count > 128 || retainedMutationCount > 4096 {
            let removed = journal.removeFirst()
            retainedMutationCount -= removed.changes.count; journalFloor = removed.revision
        }
    }

    func batch(since previous: UInt64?, epoch previousEpoch: UUID?) -> WorkspaceReadBatch {
        let reset = previousEpoch != epoch || previous == nil || previous.map { $0 < journalFloor || $0 > revision } == true
        let updates: [WorkspaceMutation]
        if reset {
            let changes = entries.values.map(WorkspaceChange.entry)
                + sessions.values.sorted { sessionOrder[$0.id, default: 0] < sessionOrder[$1.id, default: 0] }.map(WorkspaceChange.session)
                + completions.values.sorted { completionOrder[$0.id, default: 0] < completionOrder[$1.id, default: 0] }.map(WorkspaceChange.completion)
            updates = [.init(revision: revision, changes: changes)]
        } else {
            updates = journal.filter { $0.revision > (previous ?? 0) }.map { .init(revision: $0.revision, changes: $0.changes) }
        }
        return WorkspaceReadBatch(epoch: epoch, revision: revision, reset: reset, updates: updates,
                                  projects: statsProjects, historyStartedAt: historyStartedAt)
    }

    func names(projectID: String) -> [String: String] { taskNames[projectID, default: [:]] }
    func revision(on dayID: String) -> UInt64 { dayRevisions[dayID, default: 0] }
    func sessions(on dayID: String) -> [RecordedSession] {
        sessionDays[dayID, default: []].compactMap { sessions[$0] }.sorted {
            $0.start == $1.start ? sessionOrder[$0.id, default: 0] < sessionOrder[$1.id, default: 0] : $0.start < $1.start
        }
    }
    func entries(on dayID: String) -> [TimesheetEntry] {
        entryDays[dayID, default: []].compactMap { entries[$0] }
    }
    func entries(on days: [String]) -> [TimesheetEntry] {
        days.flatMap { entries(on: $0) }.sorted { entryOrder[$0.id, default: 0] < entryOrder[$1.id, default: 0] }
    }

    private func retain(_ project: FocusProject) {
        projectReferences[project.id, default: 0] += 1; historicalProjects[project.id] = project
    }
    private func release(_ project: FocusProject) { projectReferences[project.id, default: 0] -= 1 }
    private func normalizedTask(_ title: String) -> String {
        if let key = normalizedTasks[title] { return key }
        if normalizedTasks.count >= 512 { normalizedTasks = [:] }
        let key = StatsQuery.taskKey(title); normalizedTasks[title] = key; return key
    }
    private func addTaskSource(_ id: String, title: String, projectID: String, priority: Int, order: Int) {
        let key = normalizedTask(title)
        let group = labels[projectID]?[key] ?? TaskLabel()
        group.add(.init(id: id, priority: priority, order: order, name: title.isEmpty ? "Unnamed task" : title))
        labels[projectID, default: [:]][key] = group
        taskNames[projectID, default: [:]][key] = group.latest?.name
    }
    private func removeTaskSource(_ id: String, title: String, projectID: String) {
        let key = normalizedTask(title)
        guard let group = labels[projectID]?[key] else { return }
        group.remove(id)
        if group.sources.isEmpty { labels[projectID]?[key] = nil }
        taskNames[projectID, default: [:]][key] = group.latest?.name
    }
}
