import AppKit
import SwiftUI

@main enum DashboardEntryPresentationChecks {
    static var rendered = 0
    static func main() {
        let app = NSApplication.shared, delegate = DashboardEntryPresentationRunner()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
    static func run() async throws {
        let workspace = StatsPreviewData.workspace(), habits = HabitStore(calendar: workspace.calendar)
        let today = workspace.today, day = TaskDay.id(for: today, calendar: workspace.calendar)
        _ = try habits.add(name: "Read and reflect", icon: .book, startDay: day, endDay: nil, goal: .amount(target: 30, unit: .minutes))
        let tasks = DailyTaskStore(archive: TaskArchive(days: [day: [FocusTask(title: "A little research", estimateMinutes: 30), FocusTask(title: "A little research", estimateMinutes: 45)]]), calendar: workspace.calendar, habits: habits)
        let linked = WorkspaceModel(ledger: workspace.ledger, calendar: workspace.calendar, date: .now, tasks: tasks, habits: habits)
        defer { workspace.shutdown(); linked.shutdown() }
        let output = URL(fileURLWithPath: "/tmp/keep-dashboard-entry-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                for page in [DashboardPage.calendar, .timesheet] {
                    try await render(DashboardView(workspace: linked, initialPage: page).padding(24).background(KeepTheme.paper).keepAppearance(appearance),
                        size: size, to: output.appendingPathComponent("\(page.rawValue)-\(name)-\(appearance.rawValue).png"))
                }
                try await render(CalendarEntryDialog(workspace: linked, initialDate: today).keepAppearance(appearance),
                    size: size, to: output.appendingPathComponent("dialog-\(name)-\(appearance.rawValue).png"))
            }
        }
        for appearance in [AppAppearance.light, .dark] {
            try await render(ProjectPicker(projects: linked.projects, selectedProject: linked.selectedProject, showsCreation: false, onSelect: { _ in }).keepAppearance(appearance),
                size: NSSize(width: 390, height: 410), to: output.appendingPathComponent("entry-project-picker-\(appearance.rawValue).png"))
            try await render(TaskDatePicker(date: today, calendar: linked.calendar, confirmationTitle: "Use date", latestDate: today, onChoose: { _ in }).keepAppearance(appearance),
                size: NSSize(width: 390, height: 500), to: output.appendingPathComponent("entry-date-picker-\(appearance.rawValue).png"))
            let suggestions = linked.entryTaskSuggestions(on: today, projectID: FocusProject.defaults[0].id)
            try await render(CalendarEntryTaskPicker(name: .constant("research"), suggestions: suggestions, onSelect: { _ in }, onUseName: {}, onClose: {}).keepAppearance(appearance),
                size: NSSize(width: 400, height: 350), to: output.appendingPathComponent("entry-task-matches-\(appearance.rawValue).png"))
            try await render(CalendarEntryTaskPicker(name: .constant("A completely new task"), suggestions: suggestions, onSelect: { _ in }, onUseName: {}, onClose: {}).keepAppearance(appearance),
                size: NSSize(width: 400, height: 240), to: output.appendingPathComponent("entry-task-new-\(appearance.rawValue).png"))
        }
        print("Rendered \(rendered) native added entry, Calendar and Timesheet layouts in \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_DASHBOARD_ENTRY_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated added entry checks"
            window.contentView = NSHostingView(rootView: DashboardView(workspace: linked, initialPage: .calendar).padding(24).background(KeepTheme.paper).keepAppearance(.light))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive added entry fixture ready.\n".utf8))
            let seconds = Double(ProcessInfo.processInfo.environment["KEEP_DASHBOARD_ENTRY_UI_SECONDS"] ?? "100") ?? 100
            try await Task.sleep(for: .seconds(seconds)); window.close()
        }
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
        host.sizingOptions = []; window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(400)); host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size, "Added entry layouts preserve viewport bounds")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); rendered += 1
    }
}
@MainActor private final class DashboardEntryPresentationRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await DashboardEntryPresentationChecks.run() }
            catch { preconditionFailure("Added entry presentation failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
