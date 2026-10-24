import AppKit
import SwiftUI

/// Isolated native renders; never opens live archives or starts recording/playback.
@main enum ProjectPresentationChecks {
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-project-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        _ = try workspace.createProject(name: "A longer project name that should stay readable in a narrow window", accent: .denim)
        try workspace.updateProjectTargets(projectID: FocusProject.defaults[0].id, targets: .init(goal: 600, minimum: 120))
        try workspace.updateProject(FocusProject.defaults[0], name: "Keep", accent: .terracotta, hourlyRate: .init(amount: 80, currency: "EUR"))
        let now = Date.now
        var statsLedger = workspace.ledger
        for (project, seconds) in [(workspace.projects[0], 5400.0), (workspace.projects.last ?? .habits, 1800.0)] {
            statsLedger.record(project: project, from: now.addingTimeInterval(-7200), seconds: seconds, calendar: workspace.calendar, sessionID: UUID(), task: "Planning")
        }
        let statsWorkspace = WorkspaceModel(ledger: statsLedger, date: now)
        if CommandLine.arguments.contains("--interactive") {
            showInteractive(workspace: statsWorkspace)
            return
        }
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(DashboardView(workspace: workspace, initialPage: .projects)
                    .frame(width: size.width - 80, height: size.height - 80).clipped()
                    .padding(40).background(KeepTheme.paper).keepAppearance(appearance), size: size,
                    url: output.appendingPathComponent("projects-\(name)-\(appearance.rawValue).png"))
            }
            let colors = Set(workspace.projects.map(\.accent))
            try await render(ProjectEditorDialog(usedColors: colors) { _, _, _ in }.keepAppearance(appearance),
                             size: NSSize(width: 420, height: 620), url: output.appendingPathComponent("create-\(appearance.rawValue).png"))
            try await render(ProjectEditorDialog(project: workspace.projects.last, usedColors: colors) { _, _, _ in }.keepAppearance(appearance),
                             size: NSSize(width: 420, height: 620), url: output.appendingPathComponent("edit-\(appearance.rawValue).png"))
            try await render(ProjectEditorDialog(project: .habits, usedColors: colors) { _, _, _ in }.keepAppearance(appearance),
                             size: NSSize(width: 420, height: 440), url: output.appendingPathComponent("habits-\(appearance.rawValue).png"))
            try await render(ProjectCurrencyPicker(selection: "EUR") { _ in }.keepAppearance(appearance),
                             size: NSSize(width: 330, height: 390), url: output.appendingPathComponent("currencies-\(appearance.rawValue).png"))
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("full", NSSize(width: 1000, height: 3300))] {
                try await render(StatsView(workspace: statsWorkspace, tasks: DailyTaskStore(), habits: HabitStore(), preferences: AppPreferences(), isVisible: true)
                    .padding(24).background(KeepTheme.paper).keepAppearance(appearance), size: size,
                    url: output.appendingPathComponent("cost-stats-\(name)-\(appearance.rawValue).png"))
            }
            try await render(ProjectDeletionDialog(project: workspace.projects.last ?? .defaults[0], canDelete: true, onDelete: {}).keepAppearance(appearance),
                             size: NSSize(width: 420, height: 260), url: output.appendingPathComponent("delete-\(appearance.rawValue).png"))
        }
        print("Rendered 22 native project layouts in \(output.path)")
    }
    static func showInteractive(workspace: WorkspaceModel) {
        let preferences = AppPreferences(); preferences.dashboardPage = .projects
        let root = AppShellView(initialTab: .dashboard, workspace: workspace, preferences: preferences)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Keep Project Review — isolated data"
        window.contentView = NSHostingView(rootView: root)
        window.minSize = NSSize(width: 680, height: 650)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        NSApplication.shared.run()
    }
    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root); window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(350))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close()
    }
}
