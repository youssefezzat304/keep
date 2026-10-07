import AppKit
import Combine
import Observation
import OSLog
import Sparkle

/// One updater for the whole app. Sparkle owns its schedule, settings and installer.
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    enum Status: Equatable {
        case idle, checking, noUpdate
        case available(String)
        case failed
    }

    let configuration: UpdateConfiguration
    let restartGate: UpdateRestartGate
    private(set) var isStarted = false
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var lastChecked: Date?
    private(set) var status: Status = .idle
    @ObservationIgnored private weak var preferences: AppPreferences?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.youssef.keep", category: "Updates")

    init(configuration: UpdateConfiguration = UpdateConfiguration(), workspace: WorkspaceModel? = nil, preferences: AppPreferences? = nil) {
        self.configuration = configuration
        self.preferences = preferences
        restartGate = UpdateRestartGate(needsConfirmation: { [weak workspace] in
            guard let workspace else { return false }
            return [workspace.pomodoro.phase(), workspace.flow.phase()].contains { $0 == .running || $0 == .stopped }
        }, prepare: { [weak workspace] in
            // Route settlement through the same recorder and save before termination.
            workspace?.stopBothTimers()
            return workspace?.persistenceError == nil
        })
        super.init()
    }

    var statusText: String {
        if configuration.isDevelopmentBuild { return "Updates are disabled in development builds." }
        if !configuration.isValid { return "Updates aren’t available in this build." }
        if restartGate.isPending { return "An update is ready. Restart Keep when you’re ready." }
        switch status {
        case .idle: return automaticallyChecksForUpdates
            ? "Keep checks every six hours while it’s open. You choose when to install."
            : "Automatic checks are off. You can check for updates anytime."
        case .checking: return "Checking for updates…"
        case .noUpdate: return "No newer compatible update was found."
        case .available(let version): return "Keep \(version) is available."
        case .failed: return "The update couldn’t be completed. Check your connection and try again."
        }
    }

    func start() {
        guard !isStarted, !configuration.isDevelopmentBuild, configuration.isValid else { return }
        if controller == nil {
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            observe(controller.updater)
        }
        guard let controller else { return }
        do {
            try controller.updater.start()
            isStarted = true
            status = .idle
        } catch {
            status = .failed
            log(error)
        }
    }

    func checkForUpdates() {
        guard isStarted, canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isStarted else { return }
        // Use Sparkle's persisted setting; never mirror it in AppPreferences.
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func requestRestart() {
        guard restartGate.isPending else { return }
        var confirmed = !restartGate.requiresConfirmation
        if !confirmed {
            let alert = NSAlert()
            alert.messageText = "Restart Keep to install the update?"
            alert.informativeText = "Your timers will stop. Recorded time stays saved, but the current timers won’t resume after restarting."
            alert.addButton(withTitle: "Stop timers and restart")
            alert.addButton(withTitle: "Later")
            alert.window.appearance = alertAppearance
            NSApp.activate()
            confirmed = alert.runModal() == .alertFirstButtonReturn
        }
        guard confirmed else { return }
        if !restartGate.resume(confirmed: true) {
            let alert = NSAlert()
            alert.messageText = "Keep couldn’t save your recorded time."
            alert.informativeText = "Retry saving in the workspace, then restart to update from Settings."
            alert.window.appearance = alertAppearance
            alert.runModal()
        }
    }

    private var alertAppearance: NSAppearance? {
        switch preferences?.appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        case nil: NSApp.keyWindow?.effectiveAppearance
        }
    }

    private func observe(_ updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.canCheckForUpdates = value } }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.automaticallyChecksForUpdates = value } }
            .store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.lastChecked = value } }
            .store(in: &subscriptions)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        status = .checking
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .noUpdate
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if error == nil, status == .checking { status = .idle }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let failure = error as NSError
        if failure.domain == SUSparkleErrorDomain {
            if failure.code == SUError.noUpdateError.rawValue { status = .noUpdate; return }
            if failure.code == SUError.installationCanceledError.rawValue {
                restartGate.cancel()
                status = .idle
                return
            }
        }
        restartGate.cancel()
        status = .failed
        log(error)
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        restartGate.postpone(installHandler)
        // Let Sparkle finish entering its postponed state before invoking its continuation.
        DispatchQueue.main.async { [weak self] in self?.requestRestart() }
        return true
    }

    private func log(_ error: Error) {
        let error = error as NSError
        logger.error("Sparkle error: \(error.domain, privacy: .public) (\(error.code))")
    }
}
