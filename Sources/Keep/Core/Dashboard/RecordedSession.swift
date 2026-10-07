import Foundation

/// Actual timer intervals, saved alongside daily totals. Manual totals have no timestamps.
nonisolated struct RecordedSession: Identifiable, Codable, Sendable {
    enum Source: String, Codable, Sendable {
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

    /// Time fields use the recorded timezone, including a 24:00 endpoint at midnight.
    func date(for input: String, isEnd: Bool) -> Date? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = isEnd ? end : start
        if input == (isEnd ? editableEndTime : startTime) { return original }
        let parts = input.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), minute < 60 else { return nil }
        let second = parts.count == 3 ? Int(parts[2]) : 0
        guard let second, second < 60,
              let day = localCalendar.dateInterval(of: .day, for: start) else { return nil }
        if isEnd && hour == 24 && minute == 0 && second == 0 { return day.end }
        guard hour < 24,
              let value = localCalendar.nextDate(after: day.start.addingTimeInterval(-1),
                matching: DateComponents(hour: hour, minute: minute, second: second),
                matchingPolicy: .strict, repeatedTimePolicy: .first), value < day.end else { return nil }
        return value
    }

    var editableEndTime: String {
        localCalendar.dateInterval(of: .day, for: start)?.end == end ? "24:00:00" : endTime
    }

    func replacingTimes(start: Date, end: Date) throws -> RecordedSession {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              start >= .distantPast, end <= .distantFuture, end > start else { throw SessionEditError.invalidRange }
        guard let day = localCalendar.dateInterval(of: .day, for: self.start),
              start >= day.start, start < day.end, end <= day.end else { throw SessionEditError.outsideDay }
        return RecordedSession(id: id, recordingID: recordingID, dayID: dayID, project: project,
            task: task, source: source, timeZoneID: timeZoneID, start: start, end: end)
    }

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

enum SessionEditError: LocalizedError {
    case unavailable, missing, invalidRange, outsideDay
    var errorDescription: String? {
        switch self {
        case .unavailable: "Retry loading your workspace before changing sessions."
        case .missing: "This session was removed. Close this dialog and choose another entry."
        case .invalidRange: "The end time must be later than the start time."
        case .outsideDay: "Keep both times within this recorded day. Use 24:00 for an end at midnight."
        }
    }
}
