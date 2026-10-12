import Foundation

extension HabitArchive {
    /// Reporting projection only. The archive's saved logs always remain manual entries.
    nonisolated func effectiveProgress(recorded: [UUID: [String: Double]]) -> HabitArchive {
        var result = self
        var amounts = logs.reduce(into: [UUID: [String: Int]]()) { $0[$1.habitID, default: [:]][$1.dayID] = $1.amount }
        for habit in habits where habit.goal.minuteTarget != nil {
            for (day, seconds) in recorded[habit.id, default: [:]] {
                amounts[habit.id, default: [:]][day, default: 0] += Int(max(0, seconds) / 60)
            }
        }
        var logs: [HabitLog] = []
        for (id, days) in amounts {
            for (day, amount) in days where amount > 0 { logs.append(HabitLog(habitID: id, dayID: day, amount: amount)) }
        }
        result.logs = logs.sorted {
            if $0.dayID == $1.dayID { return $0.habitID.uuidString < $1.habitID.uuidString }
            return $0.dayID < $1.dayID
        }
        return result
    }
}
