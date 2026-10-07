import Foundation

/// Isolated fixtures; never used when loading the live app's stores.
enum StatsPreviewData {
    static func workspace(now: Date = .now) -> WorkspaceModel {
        let calendar = StatsSnapshot.calendar(.current)
        let today = calendar.startOfDay(for: now)
        var ledger = TimesheetLedger()
        ledger.beginPomodoroHistory(at: calendar.date(byAdding: .day, value: -40, to: today) ?? today)
        for offset in 1...35 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            let project = FocusProject.defaults[offset % 3]
            let minutes = Double(25 + offset % 5 * 20)
            ledger.record(project: project, from: start, seconds: minutes * 60, calendar: calendar,
                sessionID: UUID(), task: offset % 2 == 0 ? "A little reading" : "Practice and notes")
            ledger.recordCompletion(CompletedPomodoro(id: UUID(), project: project,
                task: offset % 2 == 0 ? "A little reading" : "Practice and notes", completedAt: start.addingTimeInterval(1500),
                dayID: StatsSnapshot.dayID(day, calendar: calendar), timeZoneID: calendar.timeZone.identifier, focusDuration: 1500))
        }
        return WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
    }

    static func habits(now: Date = .now) -> HabitStore {
        let calendar = StatsSnapshot.calendar(.current)
        let store = HabitStore(calendar: calendar)
        do {
            let start = calendar.date(byAdding: .day, value: -35, to: now) ?? now
            let habit = try store.add(name: "Read a little", icon: .book, startDay: StatsSnapshot.dayID(start, calendar: calendar), endDay: nil, goal: .checkIn)
            for offset in 1...30 where offset % 4 != 0 {
                if let day = calendar.date(byAdding: .day, value: -offset, to: now) {
                    _ = store.setAmount(1, habitID: habit.id, on: StatsSnapshot.dayID(day, calendar: calendar), today: now)
                }
            }
        } catch { assertionFailure("Invalid Stats preview fixture: \(error)") }
        return store
    }
}
