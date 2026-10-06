import Foundation
import Observation

@main enum HabitIdentityChecks {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        precondition(value(), message)
    }
    static func main() throws {
        let suite = "keep.habit-identity-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let today = TaskDay.date(for: "2026-10-06", calendar: calendar) else { throw CocoaError(.coderInvalidValue) }
        let persistence = HabitPersistence(defaults: defaults)
        let store = HabitStore(persistence: persistence, calendar: calendar)
        let original = try store.add(name: "Read", icon: .book, startDay: "2026-10-01", endDay: "2026-10-31",
                                     goal: .amount(target: 20, unit: .minutes), weekdays: [.tuesday, .thursday])
        let other = try store.add(name: "Gym", icon: .exercise, startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        _ = store.setAmount(20, habitID: original.id, on: "2026-10-01", today: today)
        _ = store.setAmount(12, habitID: original.id, on: "2026-10-06", today: today)
        let tasks = DailyTaskStore(calendar: calendar, habits: store)
        let beforeRows = tasks.tasks(on: "2026-10-06")
        let logs = store.archive.logs
        let activity = store.activity(today: today)
        let stats = store.statistics(for: original, month: today, today: today)
        try store.updateIdentity(habitID: original.id, name: "  Evening reading  ", icon: .sleep)
        guard let edited = store.habits.first(where: { $0.id == original.id }) else { throw CocoaError(.coderInvalidValue) }
        expect(edited.name == "Evening reading" && edited.icon == .sleep, "Rename is trimmed and icon changes")
        expect(edited.id == original.id && edited.startDay == original.startDay && edited.endDay == original.endDay,
               "Identity and civil date range stay unchanged")
        expect(edited.goal == original.goal && edited.weekdays == original.weekdays, "Goal and schedule stay locked")
        expect(store.archive.logs == logs, "Completed and partial logs stay unchanged")
        expect(store.habits.first(where: { $0.id == other.id }) == other, "Other habits stay unchanged")
        expect(store.activity(today: today).total == activity.total, "Activity totals stay unchanged")
        let afterStats = store.statistics(for: edited, month: today, today: today)
        expect(afterStats.monthlyCompletions == stats.monthlyCompletions && afterStats.monthlyRate == stats.monthlyRate
               && afterStats.currentStreak == stats.currentStreak && afterStats.bestStreak == stats.bestStreak, "Statistics stay unchanged")
        let afterRows = tasks.tasks(on: "2026-10-06")
        expect(afterRows.map(\.listID) == beforeRows.map(\.listID) && afterRows.first?.title == "Evening reading",
               "Projected task titles update without changing row identities")
        let reloaded = HabitStore(persistence: persistence, calendar: calendar)
        expect(reloaded.archive == store.archive, "Edited habit and progress persist together")
        try store.updateIdentity(habitID: original.id, name: edited.name, icon: .leaf)
        expect(store.habits.first?.icon == .leaf, "Icon-only edit permits own unchanged name")
        for invalid in ["", " \n ", String(repeating: "a", count: 81), "gym", "Gým"] {
            let before = store.archive
            do {
                try store.updateIdentity(habitID: original.id, name: invalid, icon: .heart)
                preconditionFailure("Invalid rename accepted")
            } catch is HabitError { expect(store.archive == before, "Invalid or duplicate names leave data intact") }
        }
        let before = store.archive
        do {
            try store.updateIdentity(habitID: UUID(), name: "Missing", icon: .heart)
            preconditionFailure("Missing habit accepted")
        } catch HabitError.missingHabit { expect(store.archive == before, "Missing IDs never create a new habit") }
        let corrupt = Data("invalid".utf8)
        defaults.set(corrupt, forKey: persistence.key)
        let blocked = HabitStore(persistence: persistence, calendar: calendar)
        do {
            try blocked.updateIdentity(habitID: original.id, name: "Blocked", icon: .heart)
            preconditionFailure("Protected load accepted an edit")
        } catch HabitError.unavailable { expect(defaults.data(forKey: persistence.key) == corrupt, "Corrupt archive remains protected") }
        print("Passed \(count) habit identity checks")
    }
}
