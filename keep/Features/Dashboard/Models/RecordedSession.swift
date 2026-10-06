import Foundation

/// Actual timer intervals, saved alongside daily totals. Manual totals have no timestamps.
struct RecordedSession: Identifiable, Codable {
    enum Source: String, Codable {
        case pomodoro, flow
        var title: String { self == .flow ? "Flow" : "Pomodoro focus" }
    }

    let id: String
    let recordingID: UUID
    let dayID: String
    let project: FocusProject
    let task: String
    let source: Source
    let timeZoneID: String
    let start: Date
    var end: Date
    var seconds: TimeInterval { end.timeIntervalSince(start) }
    var title: String { task.isEmpty ? project.name : task }

    // Preserve the civil day/time in which the time was recorded, as Timesheet does.
    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }
    var startMinute: Double { minute(start) }
    var endMinute: Double {
        if localCalendar.dateInterval(of: .day, for: start)?.end == end { return 1440 }
        // Repeated DST hours can move the wall clock back; keep a visible positive block.
        let wallEnd = minute(end)
        return wallEnd > startMinute ? wallEnd : min(1440, startMinute + seconds / 60)
    }
    var startTime: String { time(start) }
    var endTime: String { time(end) }
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = localCalendar
        formatter.timeZone = localCalendar.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    private func minute(_ date: Date) -> Double {
        let parts = localCalendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60 + Double(parts.nanosecond ?? 0) / 60e9
    }
}
