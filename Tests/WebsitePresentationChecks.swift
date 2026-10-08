import AppKit
import SwiftUI

/// Captures real Keep views with isolated example data and silent playback for the website.
/// Run through Tools/run-app-checks.py; no live archives, Music access or network requests.
@main enum WebsitePresentationChecks {
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-website-captures")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date.now
        let calendar = StatsSnapshot.calendar(.current)
        let today = calendar.startOfDay(for: now)
        var ledger = TimesheetLedger()
        ledger.beginPomodoroHistory(at: calendar.date(byAdding: .day, value: -190, to: today) ?? today)
        for offset in 1...190 where offset % 7 != 0 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let start = calendar.date(bySettingHour: 9 + offset % 3, minute: 0, second: 0, of: day) else {
                throw CocoaError(.coderInvalidValue)
            }
            let project = FocusProject.defaults[offset % 4]
            let task = ["Shape the next idea", "Practice a little German", "Refine the homepage", "Read and take notes"][offset % 4]
            ledger.record(project: project, from: start, seconds: Double(35 + offset % 5 * 20) * 60,
                          calendar: calendar, sessionID: UUID(), task: task)
            ledger.recordCompletion(CompletedPomodoro(id: UUID(), project: project, task: task,
                completedAt: start.addingTimeInterval(1500), dayID: TaskDay.id(for: day, calendar: calendar),
                timeZoneID: calendar.timeZone.identifier, focusDuration: 1500))
        }
        for offset in 0..<5 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let start = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: day) else {
                throw CocoaError(.coderInvalidValue)
            }
            ledger.record(project: FocusProject.defaults[(offset + 2) % 4], from: start,
                          seconds: Double(60 + offset * 10) * 60, calendar: calendar,
                          sessionID: UUID(), task: "Make room for the next idea")
        }
        let workspace = WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
        for project in workspace.projects {
            try workspace.updateProjectTargets(projectID: project.id, targets: .init(goal: 300, minimum: 120))
        }
        let habits = HabitStore(calendar: calendar)
        let startDay = TaskDay.id(for: calendar.date(byAdding: .day, value: -190, to: today) ?? today, calendar: calendar)
        for (index, entry) in [("Read a little", HabitIcon.book), ("Go for a walk", .walk), ("Make something", .write)].enumerated() {
            let habit = try habits.add(name: entry.0, icon: entry.1, startDay: startDay, endDay: nil,
                                       goal: .checkIn, weeklyTargets: .init(goal: 5, minimum: 3))
            for offset in 0...189 where (offset + index) % (index + 3) != 0 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { throw CocoaError(.coderInvalidValue) }
                _ = habits.setAmount(1, habitID: habit.id, on: TaskDay.id(for: date, calendar: calendar), today: now)
            }
        }
        let tasks = DailyTaskStore(calendar: calendar, habits: habits)
        let day = TaskDay.id(for: today, calendar: calendar)
        for title in ["Sketch the first idea", "Bring the homepage to life", "Take a proper lunch break"] { _ = tasks.add(title, on: day) }
        if let task = tasks.tasks(on: day).first { tasks.setComplete(true, taskID: task.id, on: day, today: now) }
        workspace.selectProject(FocusProject.defaults[2])
        workspace.startTask("Bring the homepage to life", timers: .focus)
        let preferences = AppPreferences()
        preferences.weeklyFocusGoalMinutes = 600
        let music = MusicPlayerModel(catalog: WebsiteCatalog(), playback: WebsitePlayback(), preferences: preferences,
                                     appleMusic: WebsiteMusic(), launchAppleMusic: {}, isMusicRunning: { false })
        music.togglePlayback()
        for _ in 0..<100 {
            if music.state == .playing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(music.state == .playing, "Website fixture must show the silent example track")
        let wallpapers = WallpaperLibrary()
        let size = NSSize(width: 1200, height: 900)
        preferences.appearance = .light
        for (name, tab) in [("focus", WorkspaceTab.focus), ("timesheet", .dashboard), ("habits", .habits), ("stats", .stats)] {
            try await render(AppShellView(initialTab: tab, workspace: workspace, music: music, tasks: tasks,
                habits: habits, preferences: preferences, wallpapers: wallpapers), size: size,
                to: output.appendingPathComponent("\(name)-light.png"))
        }
        try await render(VStack(spacing: 24) {
            NavBar(selection: .dashboard, onSelectFocus: {}, onSelectDashboard: {}, onSelectHabits: {},
                   onSelectStats: {}, onSelectSettings: {})
            DashboardView(workspace: workspace, initialPage: .calendar)
        }.padding(40).background(KeepTheme.paper).keepAppearance(.light), size: size,
            to: output.appendingPathComponent("calendar-light.png"))
        let capture = SnapshotCapture(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences)
        try await render(ExportSettingsView(capture: capture).padding(48)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(KeepTheme.paper).keepAppearance(.light),
            size: NSSize(width: 1000, height: 500), to: output.appendingPathComponent("exports-light.png"))
        try await render(MenuBarWorkspaceView(workspace: workspace, music: music, tasks: tasks,
            preferences: preferences, wallpapers: wallpapers).keepAppearance(.light), size: NSSize(width: 380, height: 680),
            to: output.appendingPathComponent("menu-light.png"))
        try await render(ZenModeView(workspace: workspace, music: music, preferences: preferences,
            wallpapers: wallpapers, onExit: {}).keepAppearance(.light), size: NSSize(width: 1440, height: 900),
            to: output.appendingPathComponent("zen.png"))
        workspace.shutdown(); wallpapers.shutdown(); await music.shutdown()?.value
        print("Captured eight light native Keep screenshots with isolated example data in \(output.path)")
    }

    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root.frame(width: size.width, height: size.height).clipped())
        view.sizingOptions = []; window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(700))
        view.layoutSubtreeIfNeeded()
        precondition(view.bounds.size == size)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close()
    }
}

private final class WebsitePlayback: MusicPlayback {
    var volume: Float = 0.5
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) { if autoplay { onEvent(.playing) } }
    func play() {}
    func pause() {}
    func stop() {}
}

private actor WebsiteMusic: AppleMusicControlling {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot { .init(state: .stopped, title: nil, artist: nil) }
}

private struct WebsiteCatalog: MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack] {
        [MusicTrack(id: "website-example", title: "A slower afternoon", artist: "Example track", permalink: nil)]
    }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { try await lofiTracks() }
    func streamURL(for track: MusicTrack) async throws -> URL {
        guard let url = URL(string: "https://example.invalid/silent-fixture") else { throw MusicFailure.unavailable }
        return url
    }
}
