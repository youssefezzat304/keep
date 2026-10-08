import Foundation

/// Aspirational and minimum amounts for one Monday–Sunday week, in the owner's unit.
nonisolated struct WeeklyTargets: Codable, Equatable, Sendable {
    static let maximumMinutes = 168 * 60
    let goal: Int
    let minimum: Int

    func isValid(maximum: Int) -> Bool {
        (1...maximum).contains(goal) && (1...goal).contains(minimum)
    }

    static func parseHours(_ value: String) -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let hours = Double(normalized), hours.isFinite, hours > 0, hours <= 168 else { return nil }
        let minutes = hours * 60
        guard minutes.rounded() >= 1 else { return nil }
        return Int(minutes.rounded())
    }

    static func parse(goal: String, minimum: String, hours: Bool, maximum: Int) throws -> WeeklyTargets {
        let g = hours ? parseHours(goal) : Int(goal.trimmingCharacters(in: .whitespacesAndNewlines))
        let m = hours ? parseHours(minimum) : Int(minimum.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let g, let m else { throw hours ? WeeklyTargetsError.invalidTime : WeeklyTargetsError.invalidAmount }
        let value = WeeklyTargets(goal: g, minimum: m)
        guard value.isValid(maximum: maximum) else { throw hours ? WeeklyTargetsError.invalidTime : WeeklyTargetsError.invalidAmount }
        return value
    }

    static func hoursText(_ minutes: Int) -> String {
        (Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

nonisolated enum WeeklyTargetsError: LocalizedError {
    case invalidTime, invalidAmount
    var errorDescription: String? {
        switch self {
        case .invalidTime: "Enter weekly amounts above zero and up to 168 hours, rounded to the nearest minute. At least must not exceed Goal."
        case .invalidAmount: "Enter positive weekly amounts. At least must not exceed Goal or the weekly unit limit."
        }
    }
}
