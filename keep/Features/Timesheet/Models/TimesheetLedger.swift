import Foundation

struct TimesheetEntry: Identifiable, Codable {
    var id: String { "\(project.id)/\(dayID)" }
    let project: FocusProject
    let dayID: String
    var seconds: TimeInterval
}

struct TimesheetRemoval {
    let project: FocusProject
    let entries: [TimesheetEntry]
    let sessions: [RecordedSession]
}

/// Numeric source of truth. UI strings and totals are derived, never stored separately.
struct TimesheetLedger: Codable {
    private(set) var entries: [TimesheetEntry] = []
    private(set) var customProjects: [FocusProject] = []
    private(set) var pomodoroSettings: PomodoroSettings?
    private(set) var sessions: [RecordedSession] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case entries, customProjects, pomodoroSettings, sessions }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([TimesheetEntry].self, forKey: .entries)
        // Existing v1 records predate project creation and contain only entries.
        customProjects = try container.decodeIfPresent([FocusProject].self, forKey: .customProjects) ?? []
        pomodoroSettings = try container.decodeIfPresent(PomodoroSettings.self, forKey: .pomodoroSettings)
        sessions = try container.decodeIfPresent([RecordedSession].self, forKey: .sessions) ?? []
    }

    mutating func setPomodoroSettings(_ settings: PomodoroSettings) {
        pomodoroSettings = settings
    }

    mutating func registerProject(_ project: FocusProject) {
        customProjects.append(project)
    }

    func seconds(projectID: String, dayID: String) -> TimeInterval {
        entries.first { $0.project.id == projectID && $0.dayID == dayID }?.seconds ?? 0
    }

    func total(dayIDs: [String], projectID: String? = nil) -> TimeInterval {
        entries.filter { dayIDs.contains($0.dayID) && (projectID == nil || $0.project.id == projectID) }
            .reduce(0) { $0 + $1.seconds }
    }

    func projects(dayIDs: [String]) -> [FocusProject] {
        var seen: Set<String> = []
        return entries.filter { dayIDs.contains($0.dayID) }
            .compactMap { seen.insert($0.project.id).inserted ? $0.project : nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    mutating func ensureEntry(project: FocusProject, on date: Date, calendar: Calendar) {
        let dayID = TimesheetWeek.dayID(for: date, calendar: calendar)
        guard !entries.contains(where: { $0.project.id == project.id && $0.dayID == dayID }) else { return }
        entries.append(TimesheetEntry(project: project, dayID: dayID, seconds: 0))
    }

    mutating func setSeconds(_ seconds: TimeInterval, project: FocusProject, dayID: String) {
        precondition(seconds.isFinite && seconds >= 0)
        if let index = entries.firstIndex(where: { $0.project.id == project.id && $0.dayID == dayID }) {
            entries[index].seconds = seconds
        } else {
            entries.append(TimesheetEntry(project: project, dayID: dayID, seconds: seconds))
        }
    }

    mutating func removeEntries(projectID: String, dayIDs: [String]) -> [TimesheetEntry] {
        let days = Set(dayIDs)
        let removed = entries.filter { $0.project.id == projectID && days.contains($0.dayID) }
        entries.removeAll { $0.project.id == projectID && days.contains($0.dayID) }
        return removed
    }

    /// Undo restores removed time while keeping any time recorded since removal.
    mutating func restoreEntries(_ removed: [TimesheetEntry]) {
        for entry in removed {
            setSeconds(seconds(projectID: entry.project.id, dayID: entry.dayID) + entry.seconds, project: entry.project, dayID: entry.dayID)
        }
    }

    mutating func removeSessions(projectID: String, dayIDs: [String]) -> [RecordedSession] {
        let days = Set(dayIDs)
        let removed = sessions.filter { $0.project.id == projectID && days.contains($0.dayID) }
        sessions.removeAll { $0.project.id == projectID && days.contains($0.dayID) }
        return removed
    }

    mutating func restoreSessions(_ removed: [RecordedSession]) {
        // A running recorder may have recreated a segment with the same identifier.
        for session in removed {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                let new = sessions.remove(at: index)
                sessions.append(session)
                sessions.append(RecordedSession(id: UUID().uuidString, recordingID: new.recordingID, dayID: new.dayID, project: new.project,
                    task: new.task, source: new.source, timeZoneID: new.timeZoneID, start: new.start, end: new.end))
            } else { sessions.append(session) }
        }
    }

    /// Split elapsed time across local midnight, including DST days of unequal length.
    mutating func record(project: FocusProject, from start: Date, seconds: TimeInterval, calendar: Calendar,
                         sessionID: UUID? = nil, task: String = "", source: RecordedSession.Source = .pomodoro) {
        guard seconds.isFinite && seconds > 0 else { return }
        var cursor = start
        var remaining = seconds
        while remaining > 0 {
            guard let day = calendar.dateInterval(of: .day, for: cursor) else { return }
            let segment = min(day.end.timeIntervalSince(cursor), remaining)
            guard segment > 0 else { return }
            let dayID = TimesheetWeek.dayID(for: cursor, calendar: calendar)
            setSeconds(self.seconds(projectID: project.id, dayID: dayID) + segment, project: project, dayID: dayID)
            if let sessionID {
                let id = "\(sessionID.uuidString)/\(dayID)"
                let end = cursor.addingTimeInterval(segment)
                if let index = sessions.indices.last, sessions[index].recordingID == sessionID, sessions[index].dayID == dayID,
                   abs(sessions[index].end.timeIntervalSince(cursor)) < 0.01 {
                    sessions[index].end = end
                } else {
                    // Discontinuous wall clocks or a removed row start a separate block.
                    let uniqueID = sessions.contains { $0.id == id } ? UUID().uuidString : id
                    sessions.append(RecordedSession(id: uniqueID, recordingID: sessionID, dayID: dayID, project: project, task: task,
                        source: source, timeZoneID: calendar.timeZone.identifier, start: cursor, end: end))
                }
            }
            remaining -= segment
            cursor = day.end
        }
    }
}

struct TimesheetDay: Identifiable {
    let date: Date
    let id: String
    let label: String
    let number: String
    let isWeekend: Bool
}

struct TimesheetWeek {
    let days: [TimesheetDay]
    let range: String
    let number: String
    var dayIDs: [String] { days.map(\.id) }

    init(containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
        let labels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        days = (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
            return TimesheetDay(date: date, id: Self.dayID(for: date, calendar: calendar), label: labels[index], number: String(format: "%02d", calendar.component(.day, from: date)), isWeekend: index >= 5)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        let end = days.last?.date ?? monday
        range = "\(formatter.string(from: monday)) – \(formatter.string(from: end)), \(calendar.component(.year, from: end))"
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        number = "W\(iso.component(.weekOfYear, from: monday))"
    }

    static func dayID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

enum TimesheetDuration {
    /// Accept h:mm or h:mm:ss. Blank clears a cell; reject negative/malformed values.
    static func parse(_ input: String) -> TimeInterval? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return 0 }
        let parts = input.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let hours = Double(parts[0]), hours <= 9999,
              let minutes = Int(parts[1]), minutes < 60 else { return nil }
        let seconds: Int
        if parts.count == 3 {
            guard let value = Int(parts[2]), value < 60 else { return nil }
            seconds = value
        } else { seconds = 0 }
        return hours * 3600 + Double(minutes * 60 + seconds)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let seconds = seconds.isFinite ? Int(min(max(0, seconds), Double(Int.max / 2)).rounded(.down)) : 0
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    static func total(_ seconds: TimeInterval) -> String {
        let seconds = seconds.isFinite ? Int(min(max(0, seconds), Double(Int.max / 2)).rounded(.down)) : 0
        if seconds < 60 { return "\(seconds)s" }
        return String(format: "%dh %02dm", seconds / 3600, seconds / 60 % 60)
    }
}
