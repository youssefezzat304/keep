import AppKit
import SwiftUI

@main enum HabitDeletionChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func main() async throws {
        _ = NSApplication.shared
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10)),
              let defaults = UserDefaults(suiteName: "keep.habit-delete.\(UUID().uuidString)") else { throw CocoaError(.coderInvalidValue) }
        let persistence = HabitPersistence(defaults: defaults)
        defer { defaults.removeObject(forKey: persistence.key) }
        let habits = HabitStore(persistence: persistence, calendar: calendar)
        let deleted = try habits.add(name: "Reading", icon: .book, startDay: "2026-10-01", endDay: nil, goal: .amount(target: 1, unit: .minutes))
        let other = try habits.add(name: "Walking", icon: .walk, startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        _ = habits.setAmount(1, habitID: other.id, on: "2026-10-19", today: date)
        _ = habits.setAmount(1, habitID: deleted.id, on: "2026-10-18", today: date)
        let tasks = DailyTaskStore(calendar: calendar, habits: habits)
        let workspace = WorkspaceModel(calendar: calendar, date: date, tasks: tasks, habits: habits)
        defer { workspace.shutdown() }
        let clock = ContinuousClock.now
        guard let row = tasks.tasks(on: "2026-10-19").first(where: { $0.habitID == deleted.id }) else { throw CocoaError(.coderInvalidValue) }
        workspace.startTask(row, on: "2026-10-19", timers: .both, at: clock, date: date)
        try workspace.setHabitNameExtension("Chapter one", habitID: deleted.id, at: clock, date: date)
        workspace.synchronize(at: clock + .seconds(60), date: date.addingTimeInterval(60))
        expect(habits.archive.consumedTimerGoals?[deleted.id] != nil, "Fixture has consumed timed progress")
        _ = habits.activity(today: date)
        workspace.deleteHabit(deleted, at: clock + .seconds(90), date: date.addingTimeInterval(90))
        expect(habits.habits == [other] && habits.archive.isValid, "Deletion removes only the selected habit and leaves a valid archive")
        expect(habits.archive.logs.allSatisfy { $0.habitID == other.id } && habits.archive.consumedTimerGoals?[deleted.id] == nil, "Manual progress and completion markers are removed")
        expect(habits.amount(for: deleted, on: "2026-10-19") == 0 && habits.activity(today: date).total == 1, "Progress and activity caches refresh")
        expect(tasks.tasks(on: "2026-10-19").map(\.habitID) == [other.id] && !tasks.tasks(on: "2026-10-20").contains(where: { $0.habitID == deleted.id }), "Past and future recurring task rows disappear")
        expect(workspace.taskReference == nil && workspace.habitNameExtension == nil && workspace.activeTaskName == "Reading - Chapter one", "Active target becomes unlinked with its displayed name preserved")
        expect(workspace.flow.phase(at: clock + .seconds(90)) == .running && workspace.pomodoro.phase(at: clock + .seconds(90)) == .running, "Both running timers continue")
        expect(abs(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } - 90) < 0.001, "Deletion settles elapsed time exactly once")
        workspace.stopBothTimers(at: clock + .seconds(120), date: date.addingTimeInterval(120))
        expect(workspace.ledger.sessions.contains { $0.taskReference == .habit(id: deleted.id) } && workspace.ledger.sessions.contains { $0.taskReference == nil }, "Historical attribution stays while new recording is unlinked")
        expect(abs(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } - 120) < 0.001, "Time before and after deletion remains recorded")
        expect(HabitStore(persistence: persistence, calendar: calendar).archive == habits.archive, "Deletion persists across reload")
        let before = habits.archive
        workspace.deleteHabit(deleted)
        expect(habits.archive == before, "Stale repeated deletion is harmless")
        let corrupt = Data("invalid".utf8)
        defaults.set(corrupt, forKey: persistence.key)
        let blocked = HabitStore(persistence: persistence, calendar: calendar)
        blocked.delete(habitID: other.id)
        expect(blocked.loadFailed && defaults.data(forKey: persistence.key) == corrupt, "Corrupt persistence remains protected")
        try await renderChecks()
        print("Passed \(checks) habit deletion checks; rendered ten native layouts in /tmp/keep-habit-deletion-renders")
    }

    static func renderChecks() async throws {
        let output = URL(fileURLWithPath: "/tmp/keep-habit-deletion-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let habits = HabitStore()
        let habit = try habits.add(name: "Reading and reflection with a longer habit name", icon: .book, startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        let workspace = WorkspaceModel(habits: habits)
        defer { workspace.shutdown() }
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(HabitTrackerView(store: habits, canDeleteHabit: workspace.canTrack, onDeleteHabit: { workspace.deleteHabit($0) })
                    .padding(32).background(KeepTheme.paper).keepAppearance(appearance), size: size,
                    to: output.appendingPathComponent("habits-\(label)-\(appearance.rawValue).png"))
            }
            try await render(HabitDeletionDialog(habit: habit, canDelete: true, onDelete: {}).keepAppearance(appearance), size: NSSize(width: 420, height: 330), to: output.appendingPathComponent("delete-\(appearance.rawValue).png"))
            try await render(HabitDeletionDialog(habit: habit, canDelete: false, onDelete: {}).keepAppearance(appearance), size: NSSize(width: 420, height: 330), to: output.appendingPathComponent("disabled-\(appearance.rawValue).png"))
        }
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: root); window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(300)); host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url)
    }
}
