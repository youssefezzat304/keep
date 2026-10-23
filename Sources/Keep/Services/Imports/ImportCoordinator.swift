import AppKit
import Observation

/// One application-owned operation shared by every Settings window.
@Observable final class ImportCoordinator {
    enum Phase: Equatable {
        case idle, loading, calculating, reviewing, backingUp, applying, success, failed
        var busy: Bool { self == .loading || self == .calculating || self == .backingUp || self == .applying }
    }
    private(set) var phase: Phase = .idle
    private(set) var review: ImportReview?
    private(set) var fileName = ""
    private(set) var message: String?
    private(set) var recoveryURL: URL?
    private(set) var source: KeepDataPayload?
    private(set) var scope = ImportScope.all
    private(set) var decisions = ImportDecisions()
    let capture: SnapshotCapture
    let gate: BackupRestoreGate
    @ObservationIgnored let files: any ImportProcessing
    @ObservationIgnored let transaction: BackupRestoreTransaction
    @ObservationIgnored private let backup: BackupModel?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let instant: () -> ContinuousClock.Instant
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var previewGeneration: UUID?

    init(capture: SnapshotCapture, gate: BackupRestoreGate, transaction: BackupRestoreTransaction, backup: BackupModel? = nil,
         files: (any ImportProcessing)? = nil, now: @escaping () -> Date = { .now }, instant: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.capture = capture; self.gate = gate; self.transaction = transaction; self.backup = backup
        self.files = files ?? ImportFiles(disk: transaction.disk, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        self.now = now; self.instant = instant
        observeGeneration()
    }
    var canChooseFile: Bool { !phase.busy && !gate.isLocked }
    var isWaitingForBackup: Bool { backup?.busy == true }
    var canApply: Bool { phase == .reviewing && review?.canApply == true && !gate.isLocked && previewGeneration == gate.generation && !isWaitingForBackup }
    var canCancel: Bool { phase != .backingUp && phase != .applying }

    private func observeGeneration() {
        withObservationTracking { _ = gate.generation } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.canCancel, self.previewGeneration != self.gate.generation, self.source != nil || self.phase == .loading {
                    self.cancel()
                    self.message = "Saved data was replaced in another operation. Choose the archive again to review against the current data."
                }
                self.observeGeneration()
            }
        }
    }

    func open(_ url: URL) {
        guard canChooseFile else { return }
        cancel()
        fileName = url.lastPathComponent; message = nil; recoveryURL = nil; review = nil; source = nil
        scope = .all; decisions = .init(); phase = .loading
        let id = UUID(); token = id; let generation = gate.generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await files.open(url, timeZone: capture.workspace.calendar.timeZone.identifier)
                try Task.checkCancellation()
                guard token == id, !gate.isLocked, gate.generation == generation else { throw ImportFailure.unavailable }
                self.source = source; previewGeneration = generation
                try await rebuild(id: id)
            } catch { finish(error, id: id) }
        }
    }
    func setScope(_ value: ImportScope) { guard !phase.busy, value != scope else { return }; scope = value; decisions = .init(); recalculate() }
    func resolve(_ id: String, _ value: ImportResolution) {
        guard !phase.busy else { return }; decisions.resolutions[id] = value; recalculate()
    }
    func rename(_ id: String, _ name: String) {
        guard !phase.busy else { return }; decisions.names[id] = name
    }
    func recalculate() {
        guard source != nil, canCancel, !gate.isLocked else { return }
        operation?.cancel(); let id = UUID(); token = id; phase = .calculating; message = nil
        operation = Task { [weak self] in
            guard let self else { return }
            do { try await rebuild(id: id) } catch { finish(error, id: id) }
        }
    }
    private func rebuild(id: UUID) async throws {
        guard let source, previewGeneration == gate.generation, !gate.isLocked else { throw ImportFailure.unavailable }
        phase = .calculating
        let local = try KeepDataPayload(capture.capture(.backup, at: instant(), date: now()))
        let value = try await files.review(source: source, local: local, scope: scope, decisions: decisions)
        try Task.checkCancellation()
        guard token == id, !gate.isLocked, previewGeneration == gate.generation else { throw ImportFailure.unavailable }
        review = value; phase = .reviewing; operation = nil
    }

    /// Confirmation authorizes this complete backup/commit operation; it outlives views.
    func apply() {
        guard canApply, let source, let approved = review else { return }
        let id = UUID(); token = id; message = nil; phase = .calculating
        operation = Task { [weak self] in
            guard let self else { return }
            var ownsGate = false
            do {
                guard !gate.isLocked, previewGeneration == gate.generation, backup?.busy != true else { throw ImportFailure.unavailable }
                let checkpoint = instant(), date = now()
                capture.workspace.stopBothTimers(at: checkpoint, date: date)
                let snapshot = try capture.capture(.backup, at: checkpoint, date: date)
                let local = try KeepDataPayload(snapshot)
                let localSettings = capture.preferences.snapshot
                gate.isLocked = true; ownsGate = true
                let fresh = try await files.review(source: source, local: local, scope: scope, decisions: decisions)
                try Task.checkCancellation()
                guard ImportMerge.equivalent(fresh.candidate, approved.candidate), fresh.issues == approved.issues,
                      fresh.blockers == approved.blockers else {
                    gate.isLocked = false; ownsGate = false; review = fresh; phase = .reviewing
                    message = "Your saved data changed while you were reviewing. Timers are now stopped. Review the updated changes and confirm again."
                    operation = nil; return
                }
                guard fresh.canApply else { throw ImportFailure.unavailable }
                phase = .backingUp
                // From here cancellation cannot interrupt a durable transaction.
                recoveryURL = try await files.saveRecovery(local, date: date)
                let bytes = try await files.candidateBytes(fresh.candidate, workspace: snapshot.workspace, settings: localSettings)
                let journal = try transaction.originalJournal(candidate: bytes)
                phase = .applying
                try await transaction.apply(journal)
                let ledger = TimesheetLedger(tracked: fresh.candidate.workspace, configuration: snapshot.workspace)
                // Install without callbacks until all owners contain the committed snapshot.
                capture.tasks.installBackup(fresh.candidate.tasks)
                capture.habits.installImportedData(fresh.candidate.habits)
                capture.preferences.installBackup(fresh.candidate.applyingContent(to: localSettings))
                capture.workspace.installBackup(ledger)
                backup?.dataDidImport()
                gate.generation = UUID(); gate.recoveryError = nil; gate.isLocked = false; ownsGate = false
                phase = .success; message = "Import complete. Recovery file: \(recoveryURL?.lastPathComponent ?? "saved on this Mac")."
                self.source = nil; review = nil; operation = nil
            } catch {
                if ownsGate {
                    if await transaction.disk.exists(transaction.journalURL) {
                        gate.recoveryError = "Import recovery is required. Restart Keep to recover safely. \(error.localizedDescription)"
                    } else { gate.isLocked = false }
                }
                finish(error, id: id)
            }
        }
    }
    private func finish(_ error: Error, id: UUID) {
        guard token == id else { return }
        phase = error is CancellationError ? .reviewing : .failed
        message = error is CancellationError ? "Import cancelled. No imported data was written." : error.localizedDescription
        operation = nil
    }
    func cancel() {
        guard canCancel else { return }
        operation?.cancel(); operation = nil; token = UUID()
        source = nil; review = nil; message = nil; phase = .idle
    }
    func revealRecovery() { if let recoveryURL { NSWorkspace.shared.activateFileViewerSelecting([recoveryURL]) } }
}
