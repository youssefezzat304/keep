import Foundation

struct TimesheetEntry: Identifiable, Codable {
    var id: String { "\(project.id)/\(dayID)" }
    let project: FocusProject
    let dayID: String
    var seconds: TimeInterval
}

/// Numeric source of truth. UI strings and totals are derived, never stored separately.
struct TimesheetLedger: Codable {
    private(set) var entries: [TimesheetEntry] = []

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

    /// Split elapsed time across local midnight, including DST days of unequal length.
    mutating func record(project: FocusProject, from start: Date, seconds: TimeInterval, calendar: Calendar) {
        guard seconds.isFinite && seconds > 0 else { return }
        var cursor = start
        var remaining = seconds
        while remaining > 0 {
            guard let day = calendar.dateInterval(of: .day, for: cursor) else { return }
            let segment = min(day.end.timeIntervalSince(cursor), remaining)
            guard segment > 0 else { return }
            let dayID = TimesheetWeek.dayID(for: cursor, calendar: calendar)
            setSeconds(self.seconds(projectID: project.id, dayID: dayID) + segment, project: project, dayID: dayID)
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
