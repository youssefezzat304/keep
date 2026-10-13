import Foundation

/// A user-entered interval uses the same civil-day/time rules as recorded sessions.
nonisolated struct CalendarEntryDraft {
    var projectID = FocusProject.unassigned.id
    var task = ""
    var date: Date
    var startTime = "09:00"
    var endTime = "10:00"
    var reference: TaskReference?

    func session(project: FocusProject, calendar: Calendar, now: Date) throws -> RecordedSession {
        guard date.timeIntervalSince1970.isFinite, date >= .distantPast, date <= .distantFuture else { throw CalendarEntryError.invalidDate }
        let day = calendar.startOfDay(for: date)
        let seed = RecordedSession(id: UUID().uuidString, recordingID: UUID(), dayID: TaskDay.id(for: day, calendar: calendar),
            project: project, task: "", source: .manual, timeZoneID: calendar.timeZone.identifier,
            start: day, end: day.addingTimeInterval(1), taskReference: reference)
        guard let start = seed.date(for: startTime, isEnd: false), let end = seed.date(for: endTime, isEnd: true) else { throw CalendarEntryError.invalidTime }
        let result = try seed.replacing(start: start, end: end, task: task)
        guard result.end <= now else { throw CalendarEntryError.futureTime }
        return result
    }
}

enum CalendarEntryError: LocalizedError {
    case invalidDate, invalidTime, futureTime, missingProject, missingTask, saveFailed
    var errorDescription: String? {
        switch self {
        case .saveFailed: "Couldn’t save this entry. Your existing history is unchanged; try adding it again."
        case .invalidDate: "Choose a valid recorded date."
        case .invalidTime: "Enter valid times as HH:mm or HH:mm:ss for this day."
        case .futureTime: "Entries record completed work. Choose an end time that has already passed."
        case .missingProject: "This project is no longer available. Choose an existing project or No project."
        case .missingTask: "This saved task or habit is no longer available. Choose another or leave the entry unlinked."
        }
    }
}
