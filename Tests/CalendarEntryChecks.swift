import AppKit
import SwiftUI

@main enum CalendarEntryChecks {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
    static func main() {
        let app = NSApplication.shared, delegate = CalendarEntryRunner()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
    static func run() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        guard let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9)) else { throw CocoaError(.coderInvalidValue) }
        let now = start.addingTimeInterval(3600), clock = ContinuousClock.now, day = "2026-10-12"
        let task = FocusTask(title: "Read", estimateMinutes: 30), habitID = UUID()
        let reference = TaskReference.task(id: task.id, dayID: day)
        var ledger = TimesheetLedger()
        ledger.record(project: .defaults[0], from: start, seconds: 120, calendar: calendar, sessionID: UUID(), task: "Read", taskReference: reference)
        ledger.record(project: .defaults[0], from: start.addingTimeInterval(300), seconds: 60, calendar: calendar, sessionID: UUID(), task: "Reading habit", taskReference: .habit(id: habitID))
        let suite = "keep.calendar-entry.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        try persistence.save(ledger)
        let tasks = DailyTaskStore(archive: TaskArchive(days: [day: [task]]), calendar: calendar)
        let workspace = WorkspaceModel(ledger: ledger, persistence: persistence, calendar: calendar, date: now, tasks: tasks)
        defer { workspace.shutdown() }
        let original = workspace.ledger.sessions[0]
        try workspace.editSession(id: original.id, start: original.start, end: original.end, task: "  Read chapter two \n", at: clock, date: now)
        let renamed = workspace.ledger.sessions[0]
        expect(renamed.task == "Read chapter two", "Calendar names trim whitespace")
        expect(renamed.id == original.id && renamed.recordingID == original.recordingID && renamed.source == original.source && renamed.taskReference == reference, "Entry editing retains recording and task identity")
        expect(renamed.start == original.start && renamed.end == original.end && close(workspace.ledger.total(dayIDs: [day]), 180), "Name-only edits preserve times and totals")
        expect(tasks.tasks(on: day).first?.title == "Read", "Entry edits do not rename the task definition")
        expect(close(workspace.readIndex.focusedSeconds(reference, on: day), 120), "Task actuals keep linked time after entry renaming")
        expect(workspace.readIndex.sessions[original.id]?.task == renamed.task, "Calendar read index receives the new name")
        expect(try persistence.load().sessions.first?.task == renamed.task, "Entry names persist")
        try workspace.editSession(id: original.id, start: original.start, end: original.end, task: " \n ", at: clock, date: now)
        expect(workspace.ledger.sessions[0].task.isEmpty && workspace.ledger.sessions[0].taskReference == reference, "Blank names are unnamed entries without losing attribution")
        try workspace.editSession(id: original.id, start: original.start, end: original.end, task: String(repeating: "a", count: 200), at: clock, date: now)
        expect(workspace.ledger.sessions[0].task.count == 200, "Allow the persisted 200-character name limit")
        do {
            try workspace.editSession(id: original.id, start: original.start, end: original.end, task: String(repeating: "a", count: 201), at: clock, date: now)
            preconditionFailure("Overlong entry name accepted")
        } catch SessionEditError.invalidTask { checks += 1 }
        expect(workspace.ledger.sessions[0].task.count == 200 && close(workspace.ledger.total(dayIDs: [day]), 180), "Invalid names leave history unchanged")
        let habit = workspace.ledger.sessions[1]
        try workspace.editSession(id: habit.id, start: habit.start, end: habit.end, task: "Habit session notes", at: clock, date: now)
        expect(workspace.ledger.sessions[1].taskReference == .habit(id: habitID) && close(workspace.readIndex.focusedSeconds(.habit(id: habitID), on: day), 60), "Habit entry labels preserve habit progress")
        try workspace.editSession(id: original.id, start: original.start, end: original.start.addingTimeInterval(90), task: "Read again", at: clock, date: now)
        expect(workspace.ledger.sessions[0].task == "Read again" && close(workspace.readIndex.focusedSeconds(reference, on: day), 90) && close(workspace.ledger.total(dayIDs: [day]), 150), "Combined name/time edits apply one duration delta")
        let live = WorkspaceModel(calendar: calendar, date: start)
        defer { live.shutdown() }
        live.setTaskName("Active task", at: clock, date: start)
        live.play(.flow, at: clock, date: start)
        live.synchronize(at: clock + .seconds(10), date: start.addingTimeInterval(10))
        let active = live.ledger.sessions[0]
        try live.editSession(id: active.id, task: "Corrected history", at: clock + .seconds(12), date: start.addingTimeInterval(12))
        live.stop(.flow, at: clock + .seconds(15), date: start.addingTimeInterval(15))
        expect(live.ledger.sessions.count == 2 && live.ledger.sessions[0].task == "Corrected history", "Live editing isolates the corrected segment")
        expect(live.ledger.sessions[1].task == "Active task" && live.taskName == "Active task", "Subsequent recording keeps the active target")
        expect(close(live.ledger.sessions[0].seconds, 12) && close(live.ledger.total(dayIDs: [day]), 15), "Name-only live edits preserve settled duration and count subsequent work once")
        print("Passed \(checks) calendar entry editing checks")

        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-calendar-entry-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                try await render(CalendarSessionDetail(workspace: workspace, selectedSession: original).keepAppearance(appearance),
                    size: size, to: output.appendingPathComponent("editor-\(name)-\(appearance.rawValue).png"))
                let long = RecordedSession(id: "long-preview", recordingID: original.recordingID, dayID: day, project: original.project,
                    task: String(repeating: "Long task name ", count: 13), source: original.source, timeZoneID: original.timeZoneID, start: original.start, end: original.end)
                try await render(CalendarSessionDetail(workspace: workspace, selectedSession: long).keepAppearance(appearance),
                    size: size, to: output.appendingPathComponent("editor-long-\(name)-\(appearance.rawValue).png"))
            }
        }
        print("Rendered 8 native calendar editors in \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_CALENDAR_ENTRY_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 680, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Keep — isolated calendar entry editor"
            window.contentView = NSHostingView(rootView: CalendarEntryFixture(workspace: workspace, session: workspace.ledger.sessions[0]))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive calendar entry fixture ready.\n".utf8))
            try await Task.sleep(for: .seconds(90)); window.close()
        }
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height).background(KeepTheme.paper))
        host.sizingOptions = []; window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close()
    }
}
private struct CalendarEntryFixture: View {
    let workspace: WorkspaceModel
    let session: RecordedSession
    @State private var editing = false
    var body: some View {
        VStack {
            Button("Edit entry") { editing = true }
            Text(workspace.readIndex.sessions[session.id]?.task ?? "Removed").accessibilityLabel("Saved entry name")
            Text(workspace.ledger.total(dayIDs: [session.dayID]).formatted()).accessibilityLabel("Saved daily seconds")
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(KeepTheme.paper)
            .sheet(isPresented: $editing) { CalendarSessionDetail(workspace: workspace, selectedSession: workspace.readIndex.sessions[session.id] ?? session) }
    }
}

@MainActor private final class CalendarEntryRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await CalendarEntryChecks.run() }
            catch { preconditionFailure("Calendar entry verification failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
