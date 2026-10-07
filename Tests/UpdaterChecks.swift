import AppKit
import Foundation

/// Run in the isolated app bundle described in docs/updates.md. Never checks a feed.
@main enum UpdaterChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) {
        checks += 1
        precondition(value, message)
    }

    static func main() async throws {
        _ = NSApplication.shared
        if CommandLine.arguments.dropFirst().first == "--reload" {
            guard Bundle.main.bundleIdentifier?.hasPrefix("local.keep.checks.") == true else {
                preconditionFailure("Use the isolated app check runner")
            }
            let restored = AppUpdater(configuration: UpdateConfiguration(isDevelopmentBuild: false))
            restored.start()
            try await Task.sleep(for: .milliseconds(100))
            precondition(restored.isStarted && !restored.automaticallyChecksForUpdates)
            return
        }
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let info: [String: Any] = ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": key,
                                   "CFBundleVersion": "2", "CFBundleShortVersionString": "1.1"]
        let valid = UpdateConfiguration(info: info, isDevelopmentBuild: false)
        expect(valid.isValid, "Valid release configuration")
        for url in ["http://example.com/feed", "https://user:password@example.com/feed", "https://example.com/feed#fragment", "$(KEEP_UPDATE_FEED_URL)", ""] {
            var invalid = info; invalid["SUFeedURL"] = url
            expect(!UpdateConfiguration(info: invalid, isDevelopmentBuild: false).isValid, "Reject insecure or unresolved feed")
        }
        for publicKey in ["", "$(KEEP_UPDATE_PUBLIC_ED_KEY)", Data(repeating: 1, count: 31).base64EncodedString()] {
            var invalid = info; invalid["SUPublicEDKey"] = publicKey
            expect(!UpdateConfiguration(info: invalid, isDevelopmentBuild: false).isValid, "Reject missing or malformed public key")
        }
        for field in ["SUFeedURL", "SUPublicEDKey", "CFBundleVersion", "CFBundleShortVersionString"] {
            var invalid = info; invalid.removeValue(forKey: field)
            expect(!UpdateConfiguration(info: invalid, isDevelopmentBuild: false).isValid, "Reject incomplete release configuration")
        }
        for field in ["CFBundleVersion", "CFBundleShortVersionString"] {
            var invalid = info; invalid[field] = ""
            expect(!UpdateConfiguration(info: invalid, isDevelopmentBuild: false).isValid, "Reject empty version")
        }
        let debug = AppUpdater(configuration: UpdateConfiguration(info: info, isDevelopmentBuild: true))
        debug.start(); debug.checkForUpdates(); debug.setAutomaticallyChecksForUpdates(true)
        expect(!debug.isStarted && !debug.canCheckForUpdates, "Development builds never start or check")
        let unconfigured = AppUpdater(configuration: UpdateConfiguration(info: [:], isDevelopmentBuild: false))
        unconfigured.start()
        expect(!unconfigured.isStarted && unconfigured.statusText.contains("aren’t available"), "Invalid builds stay unavailable")

        var busy = false
        var saveSucceeds = true
        var order: [String] = []
        let gate = UpdateRestartGate(needsConfirmation: { busy }, prepare: {
            order.append("save")
            return saveSucceeds
        })
        expect(!gate.resume(confirmed: true), "No pending installation is a no-op")
        gate.postpone { order.append("install") }
        busy = true
        expect(!gate.resume(confirmed: false) && gate.isPending && order.isEmpty, "Recheck timers at restart; Later leaves them untouched")
        saveSucceeds = false
        expect(!gate.resume(confirmed: true) && gate.isPending && order == ["save"], "Failed saving keeps continuation pending")
        saveSucceeds = true; order = []
        expect(gate.resume(confirmed: true) && order == ["save", "install"] && !gate.isPending, "Confirmed restart saves before installing")
        expect(!gate.resume(confirmed: true) && order.count == 2, "Installation continuation runs once")
        busy = false; order = []
        gate.postpone { order.append("install") }
        expect(gate.resume(confirmed: false) && order == ["save", "install"], "Idle workspace needs no confirmation")
        gate.postpone { order.append("unexpected") }; gate.cancel()
        expect(!gate.isPending && !gate.resume(confirmed: true) && !order.contains("unexpected"), "Abort discards continuation")

        let suite = "keep.updater-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let now = ContinuousClock.now
        let date = Date.now
        let workspace = WorkspaceModel(persistence: persistence, focusDuration: 100, date: date.addingTimeInterval(-20))
        let updater = AppUpdater(configuration: valid, workspace: workspace)
        workspace.startBothTimers(at: now.advanced(by: .seconds(-20)), date: date.addingTimeInterval(-20))
        updater.restartGate.postpone { order.append("saved-workspace") }
        expect(updater.restartGate.requiresConfirmation, "Running timers require restart confirmation")
        expect(!updater.restartGate.resume(confirmed: false) && workspace.flow.phase() == .running, "Later preserves recording")
        expect(updater.restartGate.resume(confirmed: true), "Confirmed workspace restart succeeds")
        expect(workspace.flow.phase() == .stopped && workspace.pomodoro.phase() == .stopped, "Both timers stop through workspace")
        let saved = try persistence.load()
        let seconds = saved.sessions.reduce(0) { $0 + $1.seconds }
        expect(seconds >= 20 && seconds < 22, "Final elapsed time saves once with Flow priority")
        expect(saved.completedPomodoros.isEmpty, "Partial Pomodoro does not become a completion")
        updater.restartGate.postpone {}
        expect(updater.restartGate.requiresConfirmation, "Paused timers also require confirmation")
        updater.restartGate.cancel()
        let reloaded = WorkspaceModel(persistence: persistence)
        expect(reloaded.flow.phase() == .idle && !reloaded.ledger.sessions.isEmpty, "Restart retains recorded history, not timer runtime")

        // Sparkle itself runs only against this temporary bundle with scheduling off.
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID.hasPrefix("local.keep.checks.") else {
            preconditionFailure("Use the isolated app check runner")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
        UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
        UserDefaults.standard.set(Date.now, forKey: "SULastCheckTime")
        let native = AppUpdater(configuration: UpdateConfiguration(isDevelopmentBuild: false))
        native.start()
        try await Task.sleep(for: .milliseconds(100))
        expect(native.isStarted && native.canCheckForUpdates, "Native Sparkle starts and publishes readiness through KVO")
        expect(!native.automaticallyChecksForUpdates, "Sparkle restores automatic-check choice")
        native.setAutomaticallyChecksForUpdates(true)
        try await Task.sleep(for: .milliseconds(50))
        expect(native.automaticallyChecksForUpdates, "Automatic-check toggle observes Sparkle's state")
        native.setAutomaticallyChecksForUpdates(false)
        try await Task.sleep(for: .milliseconds(50))
        expect(!native.automaticallyChecksForUpdates && !UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks"), "Sparkle persists disabled checks without AppPreferences")
        UserDefaults.standard.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--reload"]
        try child.run(); child.waitUntilExit()
        expect(child.terminationStatus == 0, "Sparkle's automatic-check preference survives another process")
        native.start()
        expect(native.isStarted && native.status == .idle, "Repeated startup neither checks nor interrupts runtime")
        print("Passed \(checks) updater checks")
    }
}
