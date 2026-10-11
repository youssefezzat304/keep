import AppKit
import SwiftUI

/// Isolated preferences, display-clock and native panel sizing checks; no live archives or playback.
@main enum MenuBarChecks {
    private static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }

    static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--reload" {
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]) else { throw CocoaError(.coderInvalidValue) }
            let preferences = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
            precondition(!preferences.menuBarEnabled && preferences.menuBarTimer == .flow && !preferences.menuBarShowSeconds, "Cross-process menu preference reload")
            return
        }
        let suite = "keep.menu-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let saved = AppPreferences(persistence: persistence)
        expect(saved.menuBarEnabled && saved.menuBarTimer == .pomodoro && saved.menuBarShowSeconds, "Menu bar defaults to visible Pomodoro")
        saved.menuBarEnabled = false
        saved.menuBarTimer = .flow
        saved.menuBarShowSeconds = false
        let reload = AppPreferences(persistence: persistence)
        expect(!reload.menuBarEnabled && reload.menuBarTimer == .flow && !reload.menuBarShowSeconds, "Restore saved menu preferences")
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
        legacy.removeValue(forKey: "menuBarShowSeconds")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let migrated = AppPreferences(persistence: persistence)
        expect(migrated.canEdit && migrated.menuBarEnabled && migrated.menuBarTimer == .pomodoro && migrated.menuBarShowSeconds, "Load archives without menu fields")
        legacy["menuBarTimer"] = "unknown"
        let corrupt = try JSONSerialization.data(withJSONObject: legacy)
        defaults.set(corrupt, forKey: persistence.key)
        let blocked = AppPreferences(persistence: persistence)
        blocked.menuBarEnabled = false
        blocked.menuBarTimer = .flow
        blocked.menuBarShowSeconds = false
        expect(!blocked.canEdit && defaults.data(forKey: persistence.key) == corrupt, "Invalid menu values preserve saved data and block edits")

        let selectionInstant = ContinuousClock.now
        for pomodoroPhase in [FocusTimer.Phase.idle, .running, .stopped, .completed] {
            for flowPhase in [FocusTimer.Phase.idle, .running, .stopped] {
                let pomodoro = fixture(mode: .pomodoro, phase: pomodoroPhase, at: selectionInstant)
                let flow = fixture(mode: .flow, phase: flowPhase, at: selectionInstant)
                for preference in MenuBarTimer.allCases {
                    let expected: MenuBarTimer = preference == .none ? .none
                        : pomodoroPhase == .running && flowPhase != .running ? .pomodoro
                        : flowPhase == .running && pomodoroPhase != .running ? .flow : preference
                    expect(MenuBarLabel.displayedTimer(preference: preference, pomodoro: pomodoro,
                        flow: flow, at: selectionInstant) == expected,
                        "Running timer selection for \(pomodoroPhase)/\(flowPhase), preference \(preference)")
                }
            }
        }
        for showPomodoro in [true, false] {
            for showFlow in [true, false] {
                for pomodoroPhase in [FocusTimer.Phase.idle, .running, .stopped, .completed] {
                    for flowPhase in [FocusTimer.Phase.idle, .running, .stopped] {
                        let pomodoro = fixture(mode: .pomodoro, phase: pomodoroPhase, at: selectionInstant)
                        let flow = fixture(mode: .flow, phase: flowPhase, at: selectionInstant)
                        for preference in MenuBarTimer.allCases {
                            let expected: MenuBarTimer = preference == .none || (!showPomodoro && !showFlow) ? .none
                                : !showPomodoro ? .flow : !showFlow ? .pomodoro
                                : pomodoroPhase == .running && flowPhase != .running ? .pomodoro
                                : flowPhase == .running && pomodoroPhase != .running ? .flow : preference
                            expect(MenuBarLabel.displayedTimer(preference: preference, pomodoro: pomodoro,
                                flow: flow, showPomodoroTimer: showPomodoro, showFlowTimer: showFlow, at: selectionInstant) == expected,
                                "Hidden timers never appear, including when running or preferred")
                        }
                    }
                }
            }
        }
        var breakTimer = fixture(mode: .pomodoro, phase: .completed, at: selectionInstant)
        let focusOutline = PomodoroProgressBorder.Identity(timer: breakTimer)
        breakTimer.startBreak(at: selectionInstant)
        let breakOutline = PomodoroProgressBorder.Identity(timer: breakTimer)
        expect(focusOutline != breakOutline, "A new break clears the completed focus outline even with the same interval ID")
        expect(MenuBarLabel.displayedTimer(preference: .flow, pomodoro: breakTimer,
            flow: FocusTimer(mode: .flow), at: selectionInstant) == .pomodoro,
            "A running Pomodoro break also takes priority over an idle Flow preference")
        expect(MenuBarLabel.displayedTimer(preference: .pomodoro, pomodoro: breakTimer,
            flow: FocusTimer(mode: .flow), showPomodoroTimer: false, at: selectionInstant) == .flow,
            "A hidden Pomodoro break never appears in the status readout")
        let halfBreak = selectionInstant.advanced(by: .seconds(30))
        breakTimer.stop(at: halfBreak)
        expect(breakTimer.elapsed(at: halfBreak) / breakTimer.intervalDuration == 0.5,
            "The shared outline derives break progress from its own duration")
        expect(breakTimer.elapsed(at: halfBreak.advanced(by: .seconds(300))) == 30,
            "Paused outline progress stays frozen")
        breakTimer.reset()
        expect(PomodoroProgressBorder.Identity(timer: breakTimer) != breakOutline && breakTimer.elapsed() == 0,
            "Reset clears the outline and starts a fresh identity")

        let workspace = WorkspaceModel()
        let instant = ContinuousClock.now
        let date = Date.now
        workspace.startBothTimers(at: instant, date: date)
        let later = instant.advanced(by: .seconds(3))
        workspace.synchronize(at: later, date: date.addingTimeInterval(3))
        expect(workspace.displayInstant == later, "Status labels use the existing workspace display refresh")
        expect(workspace.pomodoro.display(at: workspace.displayInstant) == "24:57" && workspace.flow.display(at: workspace.displayInstant) == "00:00:03", "Both status choices derive their text from recorded clock state")
        expect(MenuBarLabel.display(workspace.flow, showFlowSeconds: false, at: later) == "00:00", "Hide Flow seconds without rounding minutes up")
        expect(MenuBarLabel.display(workspace.flow, showFlowSeconds: true, at: later) == "00:00:03", "Show Flow seconds from the same clock")
        expect(MenuBarLabel.display(workspace.pomodoro, showFlowSeconds: false, at: later) == "24:57", "Show seconds preference never changes Pomodoro")
        workspace.stop(.flow, at: later, date: date.addingTimeInterval(3))
        expect(MenuBarLabel.displayedTimer(preference: .flow, pomodoro: workspace.pomodoro,
            flow: workspace.flow, at: workspace.displayInstant) == .pomodoro,
            "Stopping preferred Flow switches immediately to running Pomodoro")
        workspace.play(.flow, at: later, date: date.addingTimeInterval(3))
        expect(MenuBarLabel.displayedTimer(preference: .flow, pomodoro: workspace.pomodoro,
            flow: workspace.flow, at: workspace.displayInstant) == .flow,
            "Resuming Flow restores the user's preference when both run")
        for (seconds, expected) in [(59, "00:00"), (60, "00:01"), (3599, "00:59"), (3600, "01:00"), (3661, "01:01")] {
            expect(MenuBarLabel.display(workspace.flow, showFlowSeconds: false, at: instant.advanced(by: .seconds(seconds))) == expected, "Flow formatting preserves hour/minute boundaries")
        }
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
        let panelWallpapers = WallpaperLibrary()
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
                    tasks: panelTasks, preferences: panelPreferences, wallpapers: panelWallpapers))
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

    static func fixture(mode: FocusTimer.Mode, phase: FocusTimer.Phase, at instant: ContinuousClock.Instant) -> FocusTimer {
        var timer = FocusTimer(mode: mode, focusDuration: 60, breakDuration: 60)
        switch phase {
        case .idle: break
        case .running: timer.play(at: instant.advanced(by: .seconds(-20)))
        case .stopped:
            timer.play(at: instant.advanced(by: .seconds(-30)))
            timer.stop(at: instant.advanced(by: .seconds(-10)))
        case .completed:
            timer.play(at: instant.advanced(by: .seconds(-60)))
            timer.settleCompletion(at: instant)
        }
        return timer
    }
}
