import AppKit
import Observation

@Observable final class ExportModel {
    enum Status: Equatable {
        case idle, preparing, readyToSave, saving, success(String), error(String)
        var message: String? {
            switch self {
            case .idle: nil
            case .preparing: "Preparing export…"
            case .readyToSave: "Ready to save. Choose a destination."
            case .saving: "Saving export…"
            case .success(let name): "Saved \(name)."
            case .error(let message): message
            }
        }
        var busy: Bool {
            switch self { case .preparing, .readyToSave, .saving: true; default: false }
        }
    }
    var data = ExportData.calendar
    var from: Date
    var through: Date
    var projectID: String?
    var taskKeys: Set<String>?
    private(set) var status = Status.idle
    @ObservationIgnored let capture: SnapshotCapture
    @ObservationIgnored private let files: any ExportFileWriting
    @ObservationIgnored private let panel: any ExportSavePanel
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let instant: () -> ContinuousClock.Instant
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored weak var window: NSWindow?

    init(capture: SnapshotCapture, files: any ExportFileWriting = ExportFiles(), panel: any ExportSavePanel = NativeExportSavePanel(),
         now: @escaping () -> Date = { .now }, instant: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.capture = capture; self.files = files; self.panel = panel; self.now = now; self.instant = instant
        let date = now(), calendar = StatsSnapshot.calendar(capture.workspace.calendar)
        from = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        through = calendar.startOfDay(for: date)
    }
    var calendar: Calendar { StatsSnapshot.calendar(capture.workspace.calendar) }
    var request: ExportRequest { .init(data: data, from: from, through: through, projectID: projectID, taskKeys: data == .timesheet ? nil : taskKeys) }
    var valid: Bool { (try? request.validate(now: now(), calendar: calendar)) != nil }
    var projects: [StatsInput.Project] {
        _ = capture.workspace.readIndex.metadataRevision
        return capture.projects
    }
    var taskOptions: [StatsModel.TaskOption] {
        _ = capture.workspace.readIndex.metadataRevision
        return (projectID.map { capture.workspace.readIndex.names(projectID: $0) } ?? [:])
            .map { .init(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func retry() { capture.retry(); status = .idle }

    func start() {
        guard !status.busy else { return }
        let request = request, date = now(), checkpoint = instant()
        let generation = capture.gate?.generation
        let snapshot: PersistentSnapshot
        do {
            try request.validate(now: date, calendar: calendar)
            snapshot = try capture.capture(request.data == .stats ? .stats : .workspace, at: checkpoint, date: date)
        } catch { status = .error(error.localizedDescription); return }
        let id = UUID(); token = id; status = .preparing
        operation = Task { [weak self, files, panel] in
            var artifact: ExportArtifact?
            var chosenDestination: URL?
            // Native panels start access implicitly; release it even if restore/cancellation wins.
            defer { chosenDestination?.stopAccessingSecurityScopedResource() }
            do {
                let prepared = try await files.prepare(request, snapshot: snapshot)
                artifact = prepared
                try Task.checkCancellation()
                guard let self, self.current(id, generation) else { throw CancellationError() }
                self.status = .readyToSave
                let destination = try await panel.destination(filename: prepared.filename, data: request.data, window: self.window)
                chosenDestination = destination
                try Task.checkCancellation()
                guard self.current(id, generation) else { throw CancellationError() }
                if let destination {
                    self.status = .saving
                    do { try await files.save(prepared, to: destination) }
                    catch is CancellationError { throw CancellationError() }
                    catch { throw ExportFailure.saveFailed }
                    try await files.remove(prepared); artifact = nil
                    guard self.current(id, generation) else { throw CancellationError() }
                    self.status = .success(destination.lastPathComponent)
                } else {
                    try await files.remove(prepared); artifact = nil
                    self.status = .idle
                }
            } catch {
                var cleanupError: Error?
                if let artifact { do { try await files.remove(artifact) } catch { cleanupError = error } }
                guard let self, self.token == id else { return }
                if let cleanupError { self.status = .error("Couldn’t remove temporary export files. Restart Keep and try again. \(cleanupError.localizedDescription)") }
                else if error is CancellationError { self.status = .idle }
                else { self.status = .error(error.localizedDescription) }
            }
            if let self, self.token == id { self.operation = nil }
        }
    }
    private func current(_ id: UUID, _ generation: UUID?) -> Bool {
        token == id && capture.gate?.generation == generation && capture.gate?.isLocked != true
    }
    func cancel() {
        // Keep busy until the owned task has cleaned staging; a second submission cannot race it.
        operation?.cancel(); panel.cancel()
    }
}
