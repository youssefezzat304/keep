import Foundation
import ServiceManagement

@MainActor private final class FakeLoginItemService: LoginItemServicing {
    var status = SMAppService.Status.notRegistered
    var registrationStatus = SMAppService.Status.enabled
    var shouldFail = false
    var registrations = 0
    var removals = 0
    var settingsOpened = 0
    var removal: CheckedContinuation<Void, Never>?
    var holdsRemoval = false
    func register() throws {
        registrations += 1
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = registrationStatus
    }
    func unregister() async throws {
        removals += 1
        if holdsRemoval { await withCheckedContinuation { removal = $0 } }
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
    func openSettings() { settingsOpened += 1 }
}

/// Exercises a fake service only; never changes the Mac's login items.
@main enum LoginItemChecks {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        precondition(value(), message)
    }
    static func main() async {
        let service = FakeLoginItemService()
        let model = LoginItemModel(service: service)
        expect(!model.isEnabled && service.registrations == 0, "Reading status never registers on launch")
        await model.setEnabled(true)
        expect(model.isEnabled && service.registrations == 1 && !model.isChanging, "Explicit enable registers")
        await model.setEnabled(true)
        expect(service.registrations == 1, "Repeated enable is idempotent")
        await model.setEnabled(false)
        expect(!model.isEnabled && service.removals == 1, "Explicit disable unregisters")
        service.registrationStatus = .requiresApproval
        await model.setEnabled(true)
        expect(model.isEnabled && model.status == .requiresApproval, "Pending system approval is represented")
        await model.setEnabled(false)
        expect(!model.isEnabled, "Pending registration can be removed")
        service.shouldFail = true
        await model.setEnabled(true)
        expect(!model.isEnabled && model.errorMessage != nil && !model.isChanging, "Failed enable keeps actual status and allows retry")
        service.shouldFail = false
        service.registrationStatus = .enabled
        await model.setEnabled(true)
        expect(model.isEnabled && model.errorMessage == nil, "Successful retry clears error")
        service.shouldFail = true
        await model.setEnabled(false)
        expect(model.isEnabled && model.errorMessage != nil, "Failed disable never pretends it succeeded")
        service.shouldFail = false
        service.holdsRemoval = true
        let removal = Task { await model.setEnabled(false) }
        await Task.yield()
        expect(model.isChanging, "Asynchronous removal disables the control")
        let registrations = service.registrations
        await model.setEnabled(true)
        expect(service.registrations == registrations, "Overlapping changes are rejected")
        service.removal?.resume()
        await removal.value
        expect(!model.isEnabled && !model.isChanging, "Removal settles before another change")
        service.status = .enabled
        model.refresh()
        expect(model.isEnabled, "Refresh reflects changes in System Settings")
        service.status = .notFound
        model.refresh()
        expect(!model.isEnabled && model.status == .notFound, "Unavailable service is represented")
        model.openSettings()
        expect(service.settingsOpened == 1, "Recovery opens settings only on explicit action")
        print("Passed \(count) login-item checks")
    }
}
