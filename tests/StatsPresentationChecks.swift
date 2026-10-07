import AppKit
import SwiftUI

@main enum StatsPresentationChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func waitForSnapshot(_ model: StatsModel) async throws {
        for _ in 0..<100 {
            if model.snapshot != nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        preconditionFailure("Stats calculation did not publish")
    }
    static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--reload" {
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]) else { throw CocoaError(.coderInvalidValue) }
            let prefs = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
            precondition(prefs.weeklyFocusGoalMinutes == 180 && prefs.showStatsStreaks)
            return
        }
        let suite = "keep.stats-presentation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        expect(preferences.weeklyFocusGoalMinutes == nil && !preferences.showStatsStreaks, "Goal and streaks default off")
        preferences.weeklyFocusGoalMinutes = 180; preferences.showStatsStreaks = true
        defaults.synchronize()
        let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["--reload", suite]
        try child.run(); child.waitUntilExit()
        expect(child.terminationStatus == 0, "Goal and streak preferences survive another process")
        preferences.weeklyFocusGoalMinutes = 0
        expect(preferences.weeklyFocusGoalMinutes == 180, "Reject invalid zero goal")
        preferences.weeklyFocusGoalMinutes = 10081
        expect(preferences.weeklyFocusGoalMinutes == 180, "Reject goal over 168 hours")
        preferences.weeklyFocusGoalMinutes = 10080
        expect(preferences.weeklyFocusGoalMinutes == 10080, "Allow maximum weekly goal")
        preferences.weeklyFocusGoalMinutes = nil
        expect(try persistence.load().weeklyFocusGoalMinutes == nil, "Remove goal persists")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.snapshot)) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "weeklyFocusGoalMinutes"); legacy.removeValue(forKey: "showStatsStreaks")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let old = AppPreferences(persistence: persistence)
        expect(old.canEdit && old.weeklyFocusGoalMinutes == nil && !old.showStatsStreaks, "Legacy preferences stay readable")
        legacy["weeklyFocusGoalMinutes"] = -1
        let corrupt = try JSONSerialization.data(withJSONObject: legacy)
        defaults.set(corrupt, forKey: persistence.key)
        let protected = AppPreferences(persistence: persistence)
        protected.weeklyFocusGoalMinutes = 60
        expect(!protected.canEdit && defaults.data(forKey: persistence.key) == corrupt, "Invalid preference load preserves bytes and blocks changes")

        let workspace = StatsPreviewData.workspace()
        let habits = StatsPreviewData.habits()
        let tasks = DailyTaskStore(habits: habits)
        let today = TaskDay.id(for: .now, calendar: tasks.calendar)
        _ = tasks.add("A saved task", on: today)
        if let task = tasks.tasks(on: today).first(where: { $0.habitID == nil }) { tasks.setComplete(true, taskID: task.id, on: today) }
        let model = StatsModel()
        model.refresh(workspace: workspace, tasks: tasks, habits: habits)
        model.query.projectID = "german"; model.query.taskKeys = ["missing"]
        model.refresh(workspace: workspace, tasks: tasks, habits: habits)
        try await waitForSnapshot(model)
        expect(model.snapshot?.total == 0, "Late first request cannot overwrite newer task filter")
        expect(model.snapshot?.tasksTotal == 1 && model.snapshot?.tasksCompleted == 1, "Task summary excludes projected habit rows")
        let prior = model.snapshot?.range
        model.query.period = .year
        model.refresh(workspace: workspace, tasks: tasks, habits: habits)
        model.cancel()
        try await Task.sleep(for: .milliseconds(60))
        expect(model.snapshot == nil || model.snapshot?.range == prior, "Canceled hidden page cannot publish")
        model.query = StatsQuery()
        model.refresh(workspace: workspace, tasks: tasks, habits: habits)
        try await waitForSnapshot(model)
        expect((model.snapshot?.total ?? 0) > 0, "Returning to visible page refreshes")
        let other = StatsModel(); other.query.period = .month
        other.refresh(workspace: workspace, tasks: tasks, habits: habits)
        try await waitForSnapshot(other)
        expect(model.query.period == .week && other.query.period == .month, "Window filter state stays independent")

        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-stats-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                let prefs = AppPreferences(); prefs.appearance = appearance
                try await render(AppShellView(initialTab: .stats, workspace: workspace, tasks: tasks, habits: habits, preferences: prefs), size: size,
                    url: output.appendingPathComponent("stats-\(name)-\(appearance.rawValue).png"))
            }
        }
        let prefs = AppPreferences(); prefs.weeklyFocusGoalMinutes = 180; prefs.showStatsStreaks = true
        try await render(StatsView(workspace: workspace, tasks: tasks, habits: habits, preferences: prefs, isVisible: true).keepAppearance(.light).padding(24).background(KeepTheme.paper),
            size: NSSize(width: 1000, height: 2800), url: output.appendingPathComponent("stats-full.png"))
        try await render(StatsView(workspace: WorkspaceModel(), tasks: DailyTaskStore(), habits: HabitStore(), preferences: AppPreferences(), isVisible: true).keepAppearance(.light).padding(24).background(KeepTheme.paper),
            size: NSSize(width: 680, height: 1500), url: output.appendingPathComponent("stats-empty.png"))
        try await render(StatsDateRangePicker(range: StatsQuery().range(now: .now, calendar: workspace.calendar), calendar: workspace.calendar, now: .now, onApply: { _, _ in }),
            size: NSSize(width: 420, height: 350), url: output.appendingPathComponent("stats-date-picker.png"))
        try await render(StatsTaskPicker(options: [.init(id: "practice and notes", name: "Practice and notes"), .init(id: "a little reading", name: "A little reading")], selection: ["practice and notes"], onApply: { _ in }),
            size: NSSize(width: 420, height: 430), url: output.appendingPathComponent("stats-task-picker.png"))
        try await render(StatsGoalEditor(preferences: prefs), size: NSSize(width: 480, height: 320), url: output.appendingPathComponent("stats-goal-editor.png"))
        var filtered = StatsQuery(); filtered.projectID = "german"; filtered.taskKeys = ["a little reading"]
        try await render(StatsView(workspace: workspace, tasks: tasks, habits: habits, preferences: prefs, isVisible: true, initialQuery: filtered).keepAppearance(.light).padding(24).background(KeepTheme.paper),
            size: NSSize(width: 680, height: 1500), url: output.appendingPathComponent("stats-filtered.png"))
        filtered.taskKeys = nil; filtered.period = .month
        try await render(StatsView(workspace: workspace, tasks: tasks, habits: habits, preferences: prefs, isVisible: true, initialQuery: filtered).keepAppearance(.dark).padding(24).background(KeepTheme.paper),
            size: NSSize(width: 680, height: 1500), url: output.appendingPathComponent("stats-task-distribution.png"))
        defaults.set(Data([0, 1, 2]), forKey: "bad-workspace")
        defaults.set(Data([0, 1, 2]), forKey: "bad-tasks")
        defaults.set(Data([0, 1, 2]), forKey: "bad-habits")
        try await render(StatsView(workspace: WorkspaceModel(persistence: TimesheetPersistence(defaults: defaults, key: "bad-workspace")),
            tasks: DailyTaskStore(persistence: TaskPersistence(defaults: defaults, key: "bad-tasks")),
            habits: HabitStore(persistence: HabitPersistence(defaults: defaults, key: "bad-habits")), preferences: protected, isVisible: true).keepAppearance(.light).padding(24).background(KeepTheme.paper),
            size: NSSize(width: 680, height: 1500), url: output.appendingPathComponent("stats-errors.png"))
        workspace.shutdown()
        print("Passed \(checks) Stats preference/model checks; rendered 14 native layouts in \(output.path)")
    }
    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(300))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url)
        window.close()
    }
}
