import Foundation
import Observation

@Observable
final class StatsModel {
    struct TaskOption: Identifiable {
        let id: String
        let name: String
    }
    var query = StatsQuery()
    private(set) var snapshot: StatsSnapshot?
    private(set) var projects: [StatsInput.Project] = []
    private(set) var taskOptions: [TaskOption] = []
    private(set) var calculationError: String?
    @ObservationIgnored private var computation: Task<StatsSnapshot, Error>?
    @ObservationIgnored private var publication: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastQuery: StatsQuery?
    @ObservationIgnored private var pending: StatsInput?

    init(query: StatsQuery = StatsQuery()) { self.query = query }

    func refresh(workspace: WorkspaceModel, tasks: DailyTaskStore, habits: HabitStore, now: Date = .now) {
        if lastQuery != query { cancel(); snapshot = nil }
        lastQuery = query
        var catalog: [String: FocusProject] = [:]
        for project in workspace.ledger.entries.map(\.project) + workspace.ledger.sessions.map(\.project) + workspace.ledger.completedPomodoros.map(\.project) + workspace.projects + [.unassigned] {
            catalog[project.id] = project
        }
        projects = catalog.values.map { StatsInput.Project(id: $0.id, name: $0.name, accent: $0.accent.rawValue,
            deleted: workspace.ledger.deletedProjectIDs.contains($0.id)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var names: [String: String] = [:]
        if let projectID = query.projectID {
            let titles = workspace.ledger.sessions.filter { $0.project.id == projectID }.map(\.task)
                + workspace.ledger.completedPomodoros.filter { $0.project.id == projectID }.map(\.task)
                + workspace.ledger.taskActivities.filter { $0.project.id == projectID }.map(\.title)
            for title in titles { names[StatsQuery.taskKey(title)] = title.isEmpty ? "Unnamed task" : title }
            if let keys = query.taskKeys { for key in keys where names[key] == nil { names[key] = key.isEmpty ? "Unnamed task" : key } }
        }
        taskOptions = names.map { TaskOption(id: $0.key, name: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let progress = Dictionary(grouping: habits.archive.logs, by: \.habitID)
        let input = StatsInput(query: query, now: now, calendar: workspace.calendar, projects: projects,
            sessions: workspace.ledger.sessions.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, start: $0.start, end: $0.end, timeZoneID: $0.timeZoneID) },
            completions: workspace.ledger.completedPomodoros.map { .init(projectID: $0.project.id, task: $0.task, dayID: $0.dayID, date: $0.completedAt) },
            historyStartedAt: workspace.ledger.pomodoroHistoryStartedAt,
            entries: workspace.ledger.entries.map { .init(projectID: $0.project.id, dayID: $0.dayID, seconds: $0.seconds) },
            tasks: tasks.archive.days.map { day, rows in
                let ordinary = rows.filter { $0.habitID == nil }
                return .init(dayID: day, total: ordinary.count, completed: ordinary.filter(\.isComplete).count)
            },
            habits: habits.habits.map { habit in
                .init(id: habit.id, name: habit.name, icon: habit.icon.rawValue, start: habit.startDay, end: habit.endDay,
                    weekdays: Set(habit.weekdays.map(\.rawValue)), target: habit.goal.target,
                    progress: Dictionary(uniqueKeysWithValues: progress[habit.id, default: []].map { ($0.dayID, $0.amount) }))
            })
        if computation != nil { pending = input; return }
        start(input)
    }

    private func start(_ input: StatsInput) {
        let requestID = generation
        let operation = Task.detached(priority: .userInitiated) { try StatsSnapshot.make(input) }
        computation = operation
        publication = Task { @MainActor [weak self] in
            let result: Result<StatsSnapshot, Error>
            do { result = .success(try await operation.value) }
            catch { result = .failure(error) }
            guard !Task.isCancelled, let self, self.generation == requestID else { return }
            switch result {
            case .success(let value): self.snapshot = value; self.calculationError = nil
            case .failure(let error):
                if !(error is CancellationError) {
                    self.calculationError = "Couldn’t prepare your statistics. Retry to refresh this view."
                }
            }
            self.computation = nil; self.publication = nil
            if let next = self.pending { self.pending = nil; self.start(next) }
        }
    }

    func cancel() {
        generation = UUID()
        computation?.cancel(); publication?.cancel()
        computation = nil; publication = nil; pending = nil
    }
}
