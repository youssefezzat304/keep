import AppKit
import SwiftUI

@main enum HabitTaskExtensionChecks {
    static var checks = 0
    static var renders = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func main() {
        let app = NSApplication.shared, runner = HabitExtensionRunner()
        app.delegate = runner; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(runner) {}
    }

    static func run() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let day = "2026-10-13"
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 10)),
              let defaults = UserDefaults(suiteName: "keep.habit-extension.\(UUID().uuidString)") else { throw CocoaError(.coderInvalidValue) }
        let habits = HabitStore(calendar: calendar)
        let reading = try habits.add(name: "Reading", icon: .book, startDay: day, endDay: nil, goal: .amount(target: 30, unit: .minutes))
        let tasks = DailyTaskStore(calendar: calendar, habits: habits)
        let persistence = TimesheetPersistence(defaults: defaults)
        defer { defaults.removeObject(forKey: persistence.key) }
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, date: date, tasks: tasks, habits: habits)
        defer { workspace.shutdown() }
        let clock = ContinuousClock.now
        func at(_ seconds: Int) -> ContinuousClock.Instant { clock + .seconds(seconds) }
        func wall(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        guard let row = tasks.tasks(on: day).first else { throw CocoaError(.coderInvalidValue) }
        workspace.startTask(row, on: day, timers: .both, at: at(0), date: date)
        expect(workspace.selectedProject?.id == FocusProject.habits.id, "Habit launches into Habits")
        try workspace.setHabitNameExtension("  The Alchemist \n", habitID: reading.id, at: at(60), date: wall(60))
        expect(workspace.taskName == "Reading - The Alchemist" && workspace.activeTaskName == workspace.taskName, "Trim and compose the extension")
        expect(workspace.taskReference == .habit(id: reading.id) && workspace.selectedProject?.id == FocusProject.habits.id, "Keep habit and project attribution")
        expect(habits.habits[0].name == "Reading" && tasks.tasks(on: day)[0].title == "Reading", "Definition and recurring task keep their base name")
        workspace.stopBothTimers(at: at(120), date: wall(120))
        expect(workspace.ledger.sessions.map(\.task) == ["Reading", "Reading - The Alchemist"], "Settle existing time before extending the name")
        expect(workspace.ledger.sessions.allSatisfy { $0.taskReference == .habit(id: reading.id) }, "Both segments stay linked")
        expect(habits.timedSeconds(habitID: reading.id, on: day) == 120, "Overlapping timers count habit progress once")
        let saved = try persistence.load()
        expect(saved.taskActivities.first?.habitNameExtension == "The Alchemist", "Persist extension with the recent target")
        let restored = WorkspaceModel(ledger: saved, calendar: calendar, date: date, tasks: tasks, habits: habits)
        defer { restored.shutdown() }
        guard let recent = restored.taskSuggestions.first else { throw CocoaError(.coderInvalidValue) }
        restored.selectTask(recent, at: at(120), date: wall(120))
        expect(restored.activeTaskName == "Reading - The Alchemist" && restored.taskReference == .habit(id: reading.id), "Reselecting a saved target restores the extension and identity")
        try habits.updateIdentity(habitID: reading.id, name: "Evening reading", icon: .book)
        expect(restored.activeTaskName == "Evening reading - The Alchemist", "Renaming the habit preserves its extension")
        restored.selectTask(recent, at: at(120), date: wall(120))
        expect(restored.taskName == restored.activeTaskName, "Recent selection uses the current base name")
        let before = restored.ledger.sessions.count
        do {
            try restored.setHabitNameExtension(String(repeating: "x", count: 200), habitID: reading.id, at: at(120), date: wall(120))
            preconditionFailure("Overlong extension accepted")
        } catch HabitTaskNameError.tooLong { checks += 1 }
        expect(restored.habitNameExtension == "The Alchemist" && restored.ledger.sessions.count == before, "Validation does not mutate the target or history")
        do {
            try restored.setHabitNameExtension("Wrong habit", habitID: UUID(), at: at(120), date: wall(120))
            preconditionFailure("Stale habit accepted")
        } catch HabitTaskNameError.changedHabit { checks += 1 }
        let maximum = String(repeating: "é", count: 200 - "Evening reading - ".count)
        try restored.setHabitNameExtension(maximum, habitID: reading.id, at: at(120), date: wall(120))
        expect(restored.activeTaskName.count == 200, "Accept the 200-character combined name boundary")
        try restored.setHabitNameExtension(" \n ", habitID: reading.id, at: at(120), date: wall(120))
        expect(restored.activeTaskName == "Evening reading" && restored.habitNameExtension == nil, "Clearing detail returns to the linked base name")
        restored.startTask(row, on: day, timers: .flow, at: at(120), date: wall(120))
        expect(restored.habitNameExtension == nil, "A fresh recurring-task launch starts with its base name")
        restored.stopBothTimers(at: at(120), date: wall(120))
        let editor = FocusTaskEditor(); editor.begin(in: restored)
        expect(editor.editsHabitExtension && editor.nameExtension.isEmpty, "Habit editor begins with an optional empty detail")
        editor.nameExtension = "Chapter two"
        expect(editor.commit(to: restored) && restored.activeTaskName == "Evening reading - Chapter two", "Editor saves a linked extension")
        editor.begin(in: restored); editor.nameExtension = "Cancelled"; editor.cancel()
        expect(restored.habitNameExtension == "Chapter two", "Cancel leaves the target untouched")
        editor.begin(in: restored); editor.nameExtension = String(repeating: "x", count: 201)
        expect(!editor.canCommit && !editor.commit(to: restored) && restored.habitNameExtension == "Chapter two", "Invalid drafts cannot save")
        editor.cancel(); editor.begin(in: restored)
        editor.text = "A separate task"
        expect(editor.commit(to: restored) && restored.taskReference == nil && restored.habitNameExtension == nil, "Naming a different task retains the free-form path")
        let ordinary = FocusTask(title: "Reading", estimateMinutes: 10)
        let ordinaryTasks = DailyTaskStore(archive: TaskArchive(days: [day: [ordinary]]), calendar: calendar)
        let ordinaryWorkspace = WorkspaceModel(calendar: calendar, date: date, tasks: ordinaryTasks)
        defer { ordinaryWorkspace.shutdown() }
        ordinaryWorkspace.startTask(ordinary, on: day, timers: .flow, at: clock, date: date)
        editor.begin(in: ordinaryWorkspace)
        expect(!editor.editsHabitExtension, "Same-name ordinary tasks never become habits")
        let oldActivity = TaskActivity(id: UUID(), title: "Old target", project: .habits, lastUsed: date, taskReference: .habit(id: reading.id))
        let oldData = try JSONEncoder().encode(oldActivity)
        expect(try JSONDecoder().decode(TaskActivity.self, from: oldData).habitNameExtension == nil, "Older recent targets decode with no extension")
        var corrupt = saved
        corrupt.rememberTask("Reading - Bad", project: .habits, date: date, reference: .habit(id: reading.id), habitNameExtension: " ")
        do { try TimesheetPersistence.validate(corrupt); preconditionFailure("Invalid saved detail accepted") }
        catch { checks += 1 }
        print("Passed \(checks) habit task extension checks")

        let output = URL(fileURLWithPath: "/tmp/keep-habit-extension-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let visualDate = Date.now, visualDay = TaskDay.id(for: visualDate, calendar: calendar)
        let visualHabits = HabitStore(calendar: calendar)
        let visualHabit = try visualHabits.add(name: "Reading", icon: .book, startDay: visualDay, endDay: nil, goal: .amount(target: 30, unit: .minutes))
        let visualTasks = DailyTaskStore(calendar: calendar, habits: visualHabits)
        let visual = WorkspaceModel(calendar: calendar, tasks: visualTasks, habits: visualHabits)
        defer { visual.shutdown() }
        visual.startTask("Reading", timers: .both, reference: .habit(id: visualHabit.id))
        try visual.setHabitNameExtension("The Alchemist", habitID: visualHabit.id)
        let visualEditor = FocusTaskEditor(); visualEditor.begin(in: visual)
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                let content = ScrollView { VStack(spacing: 24) {
                    ActiveTargetHeader(editor: FocusTaskEditor(), workspace: visual, isCompact: size.width < 820)
                    TimerWorkspaceCard(workspace: visual, isCompact: size.width < 820)
                    Spacer(minLength: 0)
                }.padding(24) }.background(KeepTheme.paper).keepAppearance(appearance)
                try await render(content, size: size, to: output.appendingPathComponent("focus-\(label)-\(appearance.rawValue).png"))
            }
            try await render(TaskSuggestionPicker(editor: visualEditor, workspace: visual, onSubmit: {}, onSelect: { _ in }, onCancel: {}).keepAppearance(appearance),
                size: NSSize(width: 412, height: 400), to: output.appendingPathComponent("picker-\(appearance.rawValue).png"))
            visualEditor.nameExtension = String(repeating: "A long book title ", count: 12)
            try await render(HabitTaskExtensionField(editor: visualEditor, onSubmit: {}).padding(16).background(KeepTheme.surface).keepAppearance(appearance),
                size: NSSize(width: 340, height: 330), to: output.appendingPathComponent("validation-\(appearance.rawValue).png"))
            visualEditor.nameExtension = "The Alchemist"
            try await render(MenuBarTargetPicker(editor: visualEditor, workspace: visual, isVisible: true, onBack: {}, onSubmit: {}, onSelectProject: { _ in }, onSelectTask: { _ in }).background(KeepTheme.paper).keepAppearance(appearance),
                size: NSSize(width: 380, height: 680), to: output.appendingPathComponent("menu-\(appearance.rawValue).png"))
        }
        print("Rendered \(renders) habit extension layouts in \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_HABIT_EXTENSION_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 680, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated habit extension"
            window.contentView = NSHostingView(rootView: ActiveTargetHeader(editor: FocusTaskEditor(), workspace: visual, isCompact: true).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(KeepTheme.paper).keepAppearance(.light))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive habit extension fixture ready.\n".utf8))
            try await Task.sleep(for: .seconds(90)); window.close()
        }
    }

    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height)); host.sizingOptions = []
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); renders += 1
    }
}

private final class HabitExtensionRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await HabitTaskExtensionChecks.run() }
            catch { preconditionFailure("Habit extension checks failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
