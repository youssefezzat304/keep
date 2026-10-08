import AppKit
import SwiftUI

@main enum TargetsPresentationChecks {
    static var rendered = 0
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-targets-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let workspace = StatsPreviewData.workspace(), habits = StatsPreviewData.habits()
        let tasks = DailyTaskStore(habits: habits)
        for project in workspace.projects {
            try workspace.updateProjectTargets(projectID: project.id, targets: .init(goal: 600, minimum: 120))
        }
        let reading = try habits.add(name: "Reading and reflection with a longer name", icon: .book,
            startDay: "2026-01-01", endDay: nil, goal: .amount(target: 20, unit: .minutes),
            weekdays: [.monday, .wednesday, .friday], weeklyTargets: .init(goal: 180, minimum: 60))
        let sampleDate = TimesheetWeek(containing: .now, calendar: habits.calendar).days.first?.id ?? "2026-10-05"
        _ = habits.setAmount(80, habitID: reading.id, on: sampleDate)
        if ProcessInfo.processInfo.environment["KEEP_TARGETS_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
            let preferences = AppPreferences()
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated weekly targets fixture"
            window.contentView = NSHostingView(rootView: AppShellView(initialTab: .stats, workspace: workspace, tasks: tasks, habits: habits, preferences: preferences))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            print("Interactive fixture ready", terminator: "\n")
            try await Task.sleep(for: .seconds(90))
            window.close(); workspace.shutdown()
            return
        }
        for appearance in [AppAppearance.light, .dark] {
            let preferences = AppPreferences(); preferences.appearance = appearance
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(AppShellView(initialTab: .stats, workspace: workspace, tasks: tasks, habits: habits, preferences: preferences), size: size, to: output.appendingPathComponent("stats-\(label)-\(appearance.rawValue).png"))
                try await render(AppShellView(initialTab: .habits, workspace: workspace, tasks: tasks, habits: habits, preferences: preferences), size: size, to: output.appendingPathComponent("habits-\(label)-\(appearance.rawValue).png"))
            }
            var query = StatsQuery(); query.period = .year
            try await render(StatsView(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, isVisible: true, initialQuery: query)
                .padding(24).background(KeepTheme.paper).keepAppearance(appearance), size: NSSize(width: 1100, height: 3600), to: output.appendingPathComponent("stats-full-\(appearance.rawValue).png"))
            let calendar = StatsSnapshot.calendar(workspace.calendar)
            let activity = FocusActivitySnapshot(range: query.range(now: .now, calendar: calendar), now: .now, calendar: calendar)
                .filling([sampleDate: 8 * 3600, TaskDay.id(for: .now, calendar: calendar): 2 * 3600])
            try await render(StatsActivityGrid(snapshot: activity, availableWidth: 620)
                .padding(22).background(KeepTheme.surface).keepAppearance(appearance), size: NSSize(width: 620, height: 310),
                to: output.appendingPathComponent("activity-monthly-\(appearance.rawValue).png"))
            try await render(HabitActivityGrid(store: habits, today: .now, availableWidth: 576, onSelectDay: { _ in })
                .padding(22).background(KeepTheme.surface).keepAppearance(appearance), size: NSSize(width: 620, height: 310),
                to: output.appendingPathComponent("habit-activity-monthly-\(appearance.rawValue).png"))
            try await render(HabitCreationDialog(store: habits, habit: reading).keepAppearance(appearance), size: NSSize(width: 508, height: 620), to: output.appendingPathComponent("habit-edit-\(appearance.rawValue).png"))
            if let project = workspace.projects.first {
                try await render(ProjectGoalsDialog(workspace: workspace, project: project).keepAppearance(appearance), size: NSSize(width: 478, height: 450), to: output.appendingPathComponent("project-goals-\(appearance.rawValue).png"))
            }
            try await render(DashboardProjectsView(workspace: workspace).keepAppearance(appearance), size: NSSize(width: 580, height: 430), to: output.appendingPathComponent("projects-narrow-\(appearance.rawValue).png"))
            try await render(HabitStatisticsView(store: habits, habit: reading, today: .now, onLogAmount: { _ in }).padding(20).background(KeepTheme.paper).keepAppearance(appearance), size: NSSize(width: 450, height: 650), to: output.appendingPathComponent("habit-progress-\(appearance.rawValue).png"))
        }
        workspace.shutdown()
        print("Rendered \(rendered) native target/Stats layouts in \(output.path)")
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root.frame(width: size.width, height: size.height, alignment: .topLeading))
        view.sizingOptions = []; window.contentView = view; view.frame = NSRect(origin: .zero, size: size); window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(450))
        view.layoutSubtreeIfNeeded()
        precondition(view.bounds.size == size)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds), let png = { () -> Data? in
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])
        }() else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); rendered += 1
        try await Task.sleep(for: .milliseconds(50))
    }
}
