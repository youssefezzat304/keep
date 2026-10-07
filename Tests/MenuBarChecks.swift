import AppKit
import SwiftUI

/// Isolated preferences, display-clock and native panel sizing checks; no live archives or playback.
@main enum MenuBarChecks {
    private static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--reload" {
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]) else { throw CocoaError(.coderInvalidValue) }
            let preferences = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
            precondition(!preferences.menuBarEnabled && preferences.menuBarTimer == .flow, "Cross-process menu preference reload")
            return
        }
        let suite = "keep.menu-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let saved = AppPreferences(persistence: persistence)
        expect(saved.menuBarEnabled && saved.menuBarTimer == .pomodoro, "Menu bar defaults to visible Pomodoro")
        saved.menuBarEnabled = false
        saved.menuBarTimer = .flow
        let reload = AppPreferences(persistence: persistence)
        expect(!reload.menuBarEnabled && reload.menuBarTimer == .flow, "Restore saved menu preferences")
        defaults.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--reload", suite]
        try child.run()
        child.waitUntilExit()
        expect(child.terminationStatus == 0, "Menu preferences restore in another process")
        saved.menuBarTimer = .none
        let iconOnly = try persistence.load()
        expect(iconOnly.menuBarTimer == .some(.none), "Persist the icon-only choice")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved.snapshot)) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "menuBarEnabled")
        legacy.removeValue(forKey: "menuBarTimer")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let migrated = AppPreferences(persistence: persistence)
        expect(migrated.canEdit && migrated.menuBarEnabled && migrated.menuBarTimer == .pomodoro, "Load archives without menu fields")
        legacy["menuBarTimer"] = "unknown"
        let corrupt = try JSONSerialization.data(withJSONObject: legacy)
        defaults.set(corrupt, forKey: persistence.key)
        let blocked = AppPreferences(persistence: persistence)
        blocked.menuBarEnabled = false
        blocked.menuBarTimer = .flow
        expect(!blocked.canEdit && defaults.data(forKey: persistence.key) == corrupt, "Invalid menu values preserve saved data and block edits")

        let workspace = WorkspaceModel()
        let instant = ContinuousClock.now
        let date = Date.now
        workspace.startBothTimers(at: instant, date: date)
        let later = instant.advanced(by: .seconds(3))
        workspace.synchronize(at: later, date: date.addingTimeInterval(3))
        expect(workspace.displayInstant == later, "Status labels use the existing workspace display refresh")
        expect(workspace.pomodoro.display(at: workspace.displayInstant) == "24:57" && workspace.flow.display(at: workspace.displayInstant) == "00:00:03", "Both status choices derive their text from recorded clock state")
        saved.menuBarEnabled = false
        saved.menuBarTimer = .none
        expect(workspace.pomodoro.phase(at: later) == .running && workspace.flow.phase(at: later) == .running, "Hiding the menu or its timer never stops either timer")
        workspace.shutdown(at: later, date: date.addingTimeInterval(3))
        // Native MenuBarExtra first asks for a minimum size. A flexible scroll
        // fallback used to accept that zero-height proposal and render a sliver.
        _ = NSApplication.shared
        let panelWorkspace = WorkspaceModel()
        let panelTasks = DailyTaskStore()
        let panelPreferences = AppPreferences()
        let panelMusic = MusicPlayerModel(preferences: panelPreferences)
        for populated in [false, true] {
            if populated {
                let day = TaskDay.id(for: panelWorkspace.today, calendar: panelTasks.calendar)
                for _ in 0..<12 {
                    _ = panelTasks.add("A longer task that wraps onto another line inside the compact panel", on: day)
                }
                panelWorkspace.startBothTimers()
            }
            for appearance in [AppAppearance.light, .dark] {
                panelPreferences.appearance = appearance
                let host = NSHostingController(rootView: MenuBarWorkspaceView(
                    workspace: panelWorkspace, music: panelMusic,
                    tasks: panelTasks, preferences: panelPreferences))
                for proposal in [CGSize.zero, CGSize(width: 380, height: 1)] {
                    let size = host.sizeThatFits(in: proposal)
                    expect(size.width >= 320 && size.width <= 500 && size.height >= 400 && size.height <= 700,
                           "Native panel has a usable bounded viewport even under a collapsed size proposal")
                }
            }
        }
        panelWorkspace.shutdown()
        print("Passed \(checks) menu bar preference/display/layout checks")
    }
}
