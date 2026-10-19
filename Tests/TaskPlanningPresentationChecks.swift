import AppKit
import SwiftUI

@main enum TaskPlanningPresentationChecks {
    static var renders = 0
    static func main() {
        let app = NSApplication.shared
        let runner = TaskPlanningPresentationRunner(); app.delegate = runner; app.run()
        withExtendedLifetime(runner) {}
    }
    static func run() async throws {
        let directory = URL(fileURLWithPath: "/tmp/keep-task-planning-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date.now, calendar = Calendar.current
        let day = TaskDay.id(for: now, calendar: calendar)
        let task = FocusTask(title: "Write a proposal", estimateMinutes: 30)
        let long = FocusTask(title: "Read and annotate a longer chapter, including the examples and the discussion at the end", estimateMinutes: 60)
        let habits = HabitStore(calendar: calendar)
        let habit = try habits.add(name: "Reading", icon: .book, startDay: day, endDay: nil, goal: .amount(target: 30, unit: .minutes))
        _ = habits.setAmount(10, habitID: habit.id, on: day, today: now)
        let tasks = DailyTaskStore(archive: TaskArchive(days: [day: [task, long, FocusTask(title: "Plan the week")]]), calendar: calendar, habits: habits)
        let morning = calendar.startOfDay(for: now).addingTimeInterval(3600)
        var ledger = TimesheetLedger()
        ledger.record(project: FocusProject.defaults[0], from: morning, seconds: 2100, calendar: calendar, sessionID: UUID(), task: habit.name, source: .flow, taskReference: .habit(id: habit.id))
        ledger.record(project: FocusProject.defaults[0], from: morning.addingTimeInterval(3600), seconds: 2220, calendar: calendar, sessionID: UUID(), task: task.title, source: .pomodoro, taskReference: .task(id: task.id, dayID: day))
        let preferences = AppPreferences(), sounds = TimerSoundPlayer()
        let workspace = WorkspaceModel(ledger: ledger, calendar: calendar, date: now, timerPreferences: preferences, tasks: tasks, habits: habits)
        let origin = ContinuousClock.now.advanced(by: .seconds(-300))
        _ = workspace.updatePomodoroSettings(PomodoroSettings(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20, iterationsBeforeLongBreak: 4), at: origin, date: now.addingTimeInterval(-300))
        workspace.startTask(task, on: day, timers: .both, at: origin, date: now.addingTimeInterval(-300))
        workspace.synchronize(at: .now, date: now)
        let music = MusicPlayerModel(preferences: preferences), wallpapers = WallpaperLibrary()
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                let taskList = TasksCard(store: tasks, today: now, workspace: workspace) { task, timers in workspace.startTask(task, on: day, timers: timers) }
                try await render(VStack { taskList.frame(width: min(450, size.width - 48), height: min(500, size.height - 48)); Spacer(minLength: 0) }.padding(24)
                    .frame(width: size.width, height: size.height).background(KeepTheme.paper).keepAppearance(appearance), size: size,
                    to: directory.appendingPathComponent("tasks-\(name)-\(appearance.rawValue).png"))
                let focus = ScrollView { FocusSessionView(workspace: workspace, music: music, tasks: tasks, preferences: preferences, wallpapers: wallpapers, isCompact: size.width < 820, isActive: false).padding(24) }
                    .frame(width: size.width, height: size.height).background(KeepTheme.paper).keepAppearance(appearance)
                try await render(focus, size: size, to: directory.appendingPathComponent("focus-\(name)-\(appearance.rawValue).png"))
                for visible in [true, false] {
                    preferences.showPomodoroTimer = visible; preferences.showFlowTimer = true
                    let timers = ScrollView { TimerWorkspaceCard(workspace: workspace, isCompact: size.width < 820, preferences: preferences).padding(24) }
                        .frame(width: size.width, height: size.height).background(KeepTheme.paper).keepAppearance(appearance)
                    try await render(timers, size: size, to: directory.appendingPathComponent("timers-\(visible ? "both" : "flow")-\(name)-\(appearance.rawValue).png"))
                }
                preferences.showPomodoroTimer = true
            }
            let size = NSSize(width: 500, height: 600)
            let editor = VStack { TaskEstimateEditor(task: long) { title, estimate in try workspace.editTask(id: long.id, on: day, title: title, estimateMinutes: estimate) }; Spacer() }
                .frame(width: size.width, height: size.height).background(KeepTheme.paper).keepAppearance(appearance)
            try await render(editor, size: size, to: directory.appendingPathComponent("editor-\(appearance.rawValue).png"))
            let habitEditor = VStack { HabitAmountDialog(selection: HabitLogSelection(habit: habit, dayID: day), store: habits, today: now); Spacer() }
                .frame(width: size.width, height: size.height).background(KeepTheme.paper).keepAppearance(appearance)
            try await render(habitEditor, size: size, to: directory.appendingPathComponent("manual-habit-\(appearance.rawValue).png"))
        }
        FileHandle.standardOutput.write(Data("Rendered \(renders) native task planning, editor and active timer layouts in \(directory.path)\n".utf8))
        if ProcessInfo.processInfo.environment["KEEP_TASK_PLANNING_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated task planning fixture"
            window.contentView = NSHostingView(rootView: PlanningInteractiveFixture(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, window: window).environment(sounds))
            workspace.startUpdating(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive task planning fixture ready.\n".utf8))
            let reviewSeconds = Double(ProcessInfo.processInfo.environment["KEEP_TASK_PLANNING_UI_SECONDS"] ?? "100") ?? 100
            try await Task.sleep(for: .seconds(reviewSeconds)); window.close()
        }
        workspace.shutdown(); sounds.stop()
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root); window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(180)); host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size, "Task layouts preserve the viewport")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); renders += 1
    }
}
private final class TaskPlanningPresentationRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await TaskPlanningPresentationChecks.run() } catch { preconditionFailure("Planning presentation failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
private struct PlanningInteractiveFixture: View {
    let workspace: WorkspaceModel, tasks: DailyTaskStore, habits: HabitStore, preferences: AppPreferences
    let window: NSWindow
    @State private var appearance: AppAppearance = .light
    @State private var compact = false
    @State private var page = "Tasks"
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Light") { appearance = .light }; Button("Dark") { appearance = .dark }
                Button("Default") { compact = false; window.setContentSize(NSSize(width: 1000, height: 900)) }
                Button("Narrow") { compact = true; window.setContentSize(NSSize(width: 680, height: 650)) }
                ForEach(["Tasks", "Timers", "Habits"], id: \.self) { tab in Button(tab) { page = tab } }
            }
            if page == "Tasks" {
                TasksCard(store: tasks, workspace: workspace) { task, timers in workspace.startTask(task, on: TaskDay.id(for: workspace.today, calendar: tasks.calendar), timers: timers) }
            } else if page == "Timers" {
                ScrollView { TimerWorkspaceCard(workspace: workspace, isCompact: compact, preferences: preferences) }
            } else { HabitTrackerView(store: habits, canDeleteHabit: workspace.canTrack, onDeleteHabit: { workspace.deleteHabit($0) }) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(KeepTheme.paper).keepAppearance(appearance)
    }
}
