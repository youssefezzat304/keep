import Foundation

nonisolated enum TimerSound: String, CaseIterable, Sendable {
    case focusComplete = "focus-complete"
    case breakComplete = "break-complete"
    case habitComplete = "habit-complete"
    case flowReminder = "flow-reminder"

    var title: String {
        switch self {
        case .focusComplete: "Focus complete"
        case .breakComplete: "Break complete"
        case .flowReminder: "Flow reminder"
        case .habitComplete: "Timed habit complete"
        }
    }
}

/// Reminder cadence follows the Flow session's elapsed clock, never UI tick counts.
struct FlowReminderSchedule {
    nonisolated static let minuteRange = 1...1440
    private var sessionID: UUID?
    private var configuredMinutes: Int?
    private var nextElapsed: TimeInterval?

    mutating func isDue(timer: FocusTimer, minutes: Int?, at instant: ContinuousClock.Instant) -> Bool {
        let elapsed = timer.elapsed(at: instant)
        if sessionID != timer.intervalID || configuredMinutes != minutes {
            sessionID = timer.intervalID
            configuredMinutes = minutes
            nextElapsed = minutes.map { elapsed + Double($0) * 60 }
            return false
        }
        guard timer.phase(at: instant) == .running, let minutes, let nextElapsed,
              Self.minuteRange.contains(minutes), elapsed >= nextElapsed else { return false }
        let interval = Double(minutes) * 60
        // A late refresh or wake produces one nudge, without replaying missed reminders.
        self.nextElapsed = nextElapsed + (floor((elapsed - nextElapsed) / interval) + 1) * interval
        return true
    }
}
