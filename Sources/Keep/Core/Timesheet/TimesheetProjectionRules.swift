import Foundation

/// Shared recorded totals use saved project/civil-day attribution, never adjusted entries.
nonisolated enum TimesheetProjectionRules {
    static func recordedSeconds(_ sessions: [RecordedSession]) -> Double {
        sessions.reduce(0) { $0 + $1.seconds }
    }
    static func recordedByEntry(_ sessions: [RecordedSession]) throws -> [String: Double] {
        var result: [String: Double] = [:]
        for session in sessions {
            try Task.checkCancellation()
            result["\(session.project.id)/\(session.dayID)", default: 0] += session.seconds
        }
        return result
    }
}
