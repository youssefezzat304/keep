import AppKit
import SwiftUI

@main enum DashboardSessionEditingChecks {
    static var checks = 0, renders = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]) else { throw CocoaError(.coderInvalidValue) }
            precondition(AppPreferences(persistence: SettingsPersistence(defaults: defaults)).dashboardPage == .calendar)
            return
        }
        let app = NSApplication.shared, delegate = DashboardSessionRunner()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
    static func run() async throws {
        let suite = "keep.dashboard-session-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: settings)
        expect(preferences.dashboardPage == .timesheet, "Missing preference defaults to Timesheet")
        preferences.dashboardPage = .calendar
        expect(AppPreferences(persistence: settings).dashboardPage == .calendar, "Last dashboard view survives reload")
        defaults.synchronize()
        let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["reload", suite]
        try child.run(); child.waitUntilExit()
        expect(child.terminationStatus == 0, "Dashboard selection survives a new process")
        preferences.dashboardPage = .projects
        expect(AppPreferences(persistence: settings).dashboardPage == .projects, "Projects selection is remembered too")
        let portable = PortableSettings(preferences.snapshot)
        expect(!String(decoding: try JSONEncoder().encode(portable), as: UTF8.self).contains("dashboardPage"), "Navigation remains local to the device")
        expect(portable.applying(to: preferences.snapshot).dashboardPage == .projects, "Backup application preserves local navigation")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.snapshot)) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "dashboardPage")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: settings.key)
        expect(AppPreferences(persistence: settings).canEdit && AppPreferences(persistence: settings).dashboardPage == .timesheet, "Older settings load with Timesheet as default")
        legacy["dashboardPage"] = "invalid"
        let corrupt = try JSONSerialization.data(withJSONObject: legacy); defaults.set(corrupt, forKey: settings.key)
        let blocked = AppPreferences(persistence: settings); blocked.dashboardPage = .calendar
        expect(!blocked.canEdit && defaults.data(forKey: settings.key) == corrupt, "Unknown navigation values protect the archive")
        try settings.save(SettingsArchive())

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        guard let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 14)),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { throw CocoaError(.coderInvalidValue) }
        let dayID = TaskDay.id(for: yesterday, calendar: calendar), midnight = calendar.startOfDay(for: yesterday)
        let project = FocusProject.defaults[0], other = FocusProject.defaults[1]
        var ledger = TimesheetLedger()
        for (minute, duration, item, title) in [(540, 20, project, "Research"), (570, 30, project, "Review notes"), (600, 30, other, "Other project"), (630, 30, project, "Writing")] {
            ledger.record(project: item, from: midnight.addingTimeInterval(Double(minute * 60)), seconds: Double(duration * 60), calendar: calendar, sessionID: UUID(), task: title, source: .flow)
        }
        ledger.setSeconds(5400, project: project, dayID: dayID)
        let persistence = TimesheetPersistence(defaults: defaults)
        try persistence.save(ledger)
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, date: now)
        defer { workspace.shutdown() }
        let clock = ContinuousClock.now
        func dayProjection() -> TimesheetDayProjection { .init(projectID: project.id, dayID: dayID, index: workspace.readIndex) }
        func checkAgreement() {
            let daily = dayProjection(), weekly = WeeklyProjection(days: [dayID], index: workspace.readIndex)
            expect(daily.blocks.map(\.id) == weekly.calendarBlocksByDay[dayID, default: []].filter { $0.project.id == project.id }.map(\.id), "Timesheet and Calendar expose identical project blocks")
            expect(daily.total == weekly.seconds(projectID: project.id, dayID: dayID), "Editor day total matches the Timesheet cell")
        }
        checkAgreement()
        expect(dayProjection().blocks.count == 2 && dayProjection().blocks.first?.sessions.count == 2, "Another project interrupts the run before filtering")
        expect(dayProjection().recorded == 4800 && dayProjection().adjustment == 600, "Untimed adjustment is shown separately without inventing timestamps")
        guard let first = dayProjection().blocks.first?.sessions.first else { throw CocoaError(.coderInvalidValue) }
        try workspace.editSession(id: first.id, end: first.end.addingTimeInterval(-600), at: clock, date: now)
        checkAgreement()
        expect(dayProjection().recorded == 4200 && dayProjection().total == 4800 && dayProjection().adjustment == 600, "Shared session editing updates both views while preserving untimed corrections")
        guard let last = dayProjection().blocks.last?.sessions.first else { throw CocoaError(.coderInvalidValue) }
        try workspace.deleteSession(id: last.id, at: clock, date: now)
        checkAgreement()
        expect(dayProjection().blocks.count == 1 && dayProjection().adjustment == 600, "Shared deletion removes the same block from both views")
        let draft = CalendarEntryDraft(projectID: project.id, task: "Added from Timesheet", date: yesterday, startTime: "11:00", endTime: "11:15")
        _ = try workspace.addCalendarEntry(draft, at: clock, now: now)
        checkAgreement()
        expect(dayProjection().adjustment == 600, "Added timestamped entries preserve older corrections")
        let reloaded = WorkspaceModel(persistence: persistence, calendar: calendar, date: now)
        expect(TimesheetDayProjection(projectID: project.id, dayID: dayID, index: reloaded.readIndex).total == dayProjection().total, "Session edits persist across reload")
        reloaded.shutdown()
        let empty = TimesheetDayProjection(projectID: project.id, dayID: "2026-10-20", index: workspace.readIndex)
        expect(empty.blocks.isEmpty && empty.total == 0 && empty.adjustment == 0, "An empty day has no invented blocks or adjustments")
        let negative = WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
        negative.edit(seconds: 3600, project: project, dayID: dayID, at: clock, date: now)
        expect(TimesheetDayProjection(projectID: project.id, dayID: dayID, index: negative.readIndex).adjustment == -1200, "Earlier negative corrections remain visible and intact")
        negative.shutdown()
        try await presentations(workspace: workspace, project: project, dayID: dayID)
        if ProcessInfo.processInfo.environment["KEEP_SESSION_UI"] == "1" {
            try await interactive(workspace: workspace)
        }
        print("Passed \(checks) dashboard navigation and shared-session checks; rendered \(renders) layouts in /tmp/keep-dashboard-session-renders")
    }
    static func presentations(workspace: WorkspaceModel, project: FocusProject, dayID: String) async throws {
        let output = URL(fileURLWithPath: "/tmp/keep-dashboard-session-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let week = TimesheetWeek(containing: workspace.today, calendar: workspace.calendar)
        guard let day = week.days.first(where: { $0.id == dayID }), let empty = week.days.first else { throw CocoaError(.coderInvalidValue) }
        let editor = FocusTaskEditor(); editor.begin(in: workspace)
        // Enough recent targets to exercise the indicator rather than a non-scrolling list.
        for index in 0..<20 { workspace.startTask("Recent task \(index)", timers: .flow); workspace.stopBothTimers() }
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                for page in [DashboardPage.timesheet, .calendar] {
                    try await render(DashboardView(workspace: workspace, initialPage: page).padding(24).background(KeepTheme.paper).keepAppearance(appearance), size: size, url: output.appendingPathComponent("\(page)-\(label)-\(appearance.rawValue).png"))
                }
            }
            try await render(TimesheetDaySessions(workspace: workspace, project: project, day: day).keepAppearance(appearance), size: NSSize(width: 460, height: 540), url: output.appendingPathComponent("blocks-\(appearance.rawValue).png"))
            try await render(TimesheetDaySessions(workspace: workspace, project: project, day: empty).keepAppearance(appearance), size: NSSize(width: 460, height: 300), url: output.appendingPathComponent("empty-\(appearance.rawValue).png"))
            try await render(MenuBarTargetPicker(editor: editor, workspace: workspace, isVisible: true, onBack: {}, onSubmit: {}, onSelectProject: { _ in }, onSelectTask: { _ in }).padding(20).frame(width: 380, height: 680).background(KeepTheme.paper).keepAppearance(appearance), size: NSSize(width: 380, height: 680), url: output.appendingPathComponent("picker-\(appearance.rawValue).png"))
            try await render(MenuBarWorkspaceView(workspace: workspace, music: MusicPlayerModel(), tasks: DailyTaskStore(), preferences: { let p = AppPreferences(); p.appearance = appearance; return p }(), wallpapers: WallpaperLibrary()), size: NSSize(width: 380, height: 680), url: output.appendingPathComponent("menu-\(appearance.rawValue).png"))
        }
    }
    static func interactive(workspace: WorkspaceModel) async throws {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "Keep — isolated dashboard sessions"
        window.contentView = NSHostingView(rootView: SessionInteractiveFixture(workspace: workspace))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        FileHandle.standardOutput.write(Data("Dashboard session UI ready\n".utf8))
        try await Task.sleep(for: .seconds(90)); window.close()
    }
    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height)); host.sizingOptions = []
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(300)); host.layoutSubtreeIfNeeded()
        expect(host.frame.size == size, "Views preserve the requested viewport")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); renders += 1
    }
}
private struct SessionInteractiveFixture: View {
    let workspace: WorkspaceModel
    @State private var preferences = AppPreferences()
    @State private var page = "Dashboard"
    var body: some View {
        VStack {
            HStack {
                Button("Dashboard") { page = "Dashboard" }
                Button("Menu") { page = "Menu" }
                Button("Reopen dashboard") { page = "Away" }
                Button("Narrow") { NSApp.keyWindow?.setContentSize(NSSize(width: 680, height: 650)) }
                Button("Dark") { preferences.appearance = .dark }
            }
            if page == "Dashboard" { DashboardView(workspace: workspace, preferences: preferences) }
            else if page == "Menu" { MenuBarWorkspaceView(workspace: workspace, music: MusicPlayerModel(), tasks: DailyTaskStore(), preferences: preferences, wallpapers: WallpaperLibrary()) }
            else { Text("Dashboard closed. Click Dashboard to reopen.") }
        }.padding(24).background(KeepTheme.paper).keepAppearance(preferences.appearance)
    }
}
@MainActor private final class DashboardSessionRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await DashboardSessionEditingChecks.run() }
            catch { preconditionFailure("Dashboard session checks failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
