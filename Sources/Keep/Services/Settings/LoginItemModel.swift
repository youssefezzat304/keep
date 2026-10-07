import Observation
import OSLog
import ServiceManagement

@MainActor protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
    func openSettings()
}

struct SystemLoginItemService: LoginItemServicing {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// macOS owns login registration; do not duplicate its state in a preferences archive.
@Observable final class LoginItemModel {
    private(set) var status: SMAppService.Status
    private(set) var isChanging = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let service: any LoginItemServicing
    private let logger = Logger(subsystem: "com.youssef.keep", category: "LoginItem")

    init(service: (any LoginItemServicing)? = nil) {
        let service = service ?? SystemLoginItemService()
        self.service = service
        status = service.status
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status = service.status }
    func openSettings() { service.openSettings() }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        refresh()
        errorMessage = nil
        guard enabled != isEnabled else { return }
        isChanging = true
        defer { refresh(); isChanging = false }
        do {
            if enabled { try service.register() }
            else { try await service.unregister() }
        } catch {
            let diagnostic = error as NSError
            logger.error("Login item change failed: \(diagnostic.domain, privacy: .public) (\(diagnostic.code))")
            errorMessage = "Couldn’t \(enabled ? "enable" : "disable") Start on login. Try again, or manage Keep in System Settings → General → Login Items."
        }
    }
}
