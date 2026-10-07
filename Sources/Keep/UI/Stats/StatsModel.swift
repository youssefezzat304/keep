import Foundation
import Observation

@Observable final class StatsModel {
    struct TaskOption: Identifiable { let id: String; let name: String }
    var query = StatsQuery()
    private(set) var snapshot: StatsSnapshot?
    private(set) var projects: [StatsInput.Project] = []
    private(set) var taskOptions: [TaskOption] = []
    private(set) var calculationError: String?
    @ObservationIgnored private var cache = StatsCache()
    @ObservationIgnored private var computation: Task<StatsSnapshot, Error>?
    @ObservationIgnored private var publication: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastQuery: StatsQuery?
    @ObservationIgnored private var pending: Request?
    @ObservationIgnored private var cursor: (epoch: UUID, revision: UInt64)?
    @ObservationIgnored private var metadataKey: String?
    @ObservationIgnored private var taskRevision: UInt64?
    @ObservationIgnored private var habitRevision: UInt64?
    @ObservationIgnored private var preparedTasks: [StatsInput.TaskDay] = []
    @ObservationIgnored private var preparedHabits: [StatsInput.Habit] = []
    @ObservationIgnored private var owners: [ObjectIdentifier] = []
    @ObservationIgnored private var lastRequest: Stamp?

    private struct Stamp: Equatable {
        let query: StatsQuery, epoch: UUID, revision: UInt64, tasks: UInt64, habits: UInt64
        let second: Double, calendar: Calendar
    }
    private struct Request: Sendable {
        let batch: WorkspaceReadBatch, query: StatsQuery, supplement: StatsSupplement, now: Date, calendar: Calendar
    }

    init(query: StatsQuery = StatsQuery()) { self.query = query }

    func refresh(workspace: WorkspaceModel, tasks: DailyTaskStore, habits: HabitStore, now: Date = .now) {
        let sources = [ObjectIdentifier(workspace), ObjectIdentifier(tasks), ObjectIdentifier(habits)]
        if owners != sources {
            cancel(); cache = StatsCache(); cursor = nil; taskRevision = nil; habitRevision = nil; metadataKey = nil
            owners = sources
        }
        if lastQuery != query { cancel(); snapshot = nil; metadataKey = nil }
        lastQuery = query
        let index = workspace.readIndex
        let calendar = StatsSnapshot.calendar(workspace.calendar)
        let stamp = Stamp(query: query, epoch: index.epoch, revision: index.revision, tasks: tasks.revision, habits: habits.revision,
                          second: now.timeIntervalSinceReferenceDate.rounded(.down), calendar: calendar)
        guard stamp != lastRequest else { return }
        lastRequest = stamp
        let key = "\(index.epoch)/\(index.metadataRevision)/\(calendar.locale?.identifier ?? Locale.current.identifier)/\(query.projectID ?? "")"
        if metadataKey != key {
            projects = index.statsProjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            var names = query.projectID.map { index.names(projectID: $0) } ?? [:]
            if let keys = query.taskKeys { for key in keys where names[key] == nil { names[key] = key.isEmpty ? "Unnamed task" : key } }
            taskOptions = names.map { TaskOption(id: $0.key, name: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            metadataKey = key
        }
        if taskRevision != tasks.revision {
            preparedTasks = tasks.archive.days.map { day, rows in
                let ordinary = rows.filter { $0.habitID == nil }
                return .init(dayID: day, total: ordinary.count, completed: ordinary.filter(\.isComplete).count)
            }
            taskRevision = tasks.revision
        }
        if habitRevision != habits.revision {
            let progress = Dictionary(grouping: habits.archive.logs, by: \.habitID)
            preparedHabits = habits.habits.map { habit in
                .init(id: habit.id, name: habit.name, icon: habit.icon.rawValue, start: habit.startDay, end: habit.endDay,
                      weekdays: Set(habit.weekdays.map(\.rawValue)), target: habit.goal.target,
                      progress: Dictionary(uniqueKeysWithValues: progress[habit.id, default: []].map { ($0.dayID, $0.amount) }))
            }
            habitRevision = habits.revision
        }
        let request = Request(batch: index.batch(since: cursor?.revision, epoch: cursor?.epoch), query: query,
            supplement: .init(taskRevision: tasks.revision, habitRevision: habits.revision, tasks: preparedTasks, habits: preparedHabits), now: now, calendar: calendar)
        if computation != nil { pending = request; return }
        start(request)
    }

    private func start(_ request: Request) {
        let requestID = generation
        let operation = Task.detached(priority: .userInitiated) { [cache] in
            try await cache.snapshot(batch: request.batch, query: request.query, supplement: request.supplement, now: request.now, calendar: request.calendar)
        }
        computation = operation
        publication = Task { @MainActor [weak self] in
            let result: Result<StatsSnapshot, Error>
            do { result = .success(try await operation.value) }
            catch { result = .failure(error) }
            guard !Task.isCancelled, let self, self.generation == requestID else { return }
            switch result {
            case .success(let value):
                self.cursor = (request.batch.epoch, request.batch.revision)
                self.snapshot = value; self.calculationError = nil
            case .failure(let error):
                self.lastRequest = nil
                if !(error is CancellationError) { self.calculationError = "Couldn’t prepare your statistics. Retry to refresh this view." }
            }
            self.computation = nil; self.publication = nil
            if let next = self.pending { self.pending = nil; self.start(next) }
        }
    }

    func cancel() {
        generation = UUID(); lastRequest = nil
        computation?.cancel(); publication?.cancel()
        computation = nil; publication = nil; pending = nil
    }
}
