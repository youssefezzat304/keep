import Foundation

/// Foundation handles the local preferences file; no provider or account is involved.
struct TimesheetPersistence {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "keep.timesheet.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> TimesheetLedger {
        guard let data = defaults.data(forKey: key) else { return TimesheetLedger() }
        let ledger = try JSONDecoder().decode(TimesheetLedger.self, from: data)
        guard ledger.pomodoroSettings?.isValid != false else { throw CocoaError(.coderReadCorrupt) }
        var projectIDs = Set((FocusProject.defaults + [.unassigned]).map(\.id))
        guard ledger.customProjects.allSatisfy({ project in
            !project.id.isEmpty && !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            project.name.count <= 80 && project.accent != .neutral && projectIDs.insert(project.id).inserted
        }) else { throw CocoaError(.coderReadCorrupt) }
        guard ledger.deletedProjectIDs.isSubset(of: projectIDs), !ledger.deletedProjectIDs.contains(FocusProject.unassigned.id) else {
            throw CocoaError(.coderReadCorrupt)
        }
        var seen: Set<String> = []
        guard ledger.entries.allSatisfy({ entry in
            entry.seconds.isFinite && entry.seconds >= 0 && !entry.project.id.isEmpty &&
            entry.dayID.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil &&
            seen.insert(entry.id).inserted
        }) else { throw CocoaError(.coderReadCorrupt) }
        var sessionIDs: Set<String> = []
        guard ledger.sessions.allSatisfy({ session in
            guard session.start.timeIntervalSince1970.isFinite, session.end.timeIntervalSince1970.isFinite,
                  session.start >= .distantPast, session.end <= .distantFuture,
                  session.seconds > 0 else { return false }
            var calendar = Calendar(identifier: .gregorian)
            guard let zone = TimeZone(identifier: session.timeZoneID) else { return false }
            calendar.timeZone = zone
            guard let day = calendar.dateInterval(of: .day, for: session.start) else { return false }
            return !session.id.isEmpty && sessionIDs.insert(session.id).inserted &&
                !session.project.id.isEmpty && !session.project.name.isEmpty && session.task.count <= 200 &&
                session.end <= day.end &&
                TimesheetWeek.dayID(for: session.start, calendar: calendar) == session.dayID
        }) else { throw CocoaError(.coderReadCorrupt) }
        var activityIDs: Set<UUID> = []
        var activityKeys: [String: Set<String>] = [:]
        guard ledger.taskActivities.allSatisfy({ activity in
            let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return !title.isEmpty && title == activity.title && title.count <= 200 && !activity.project.id.isEmpty && !activity.project.name.isEmpty &&
                activity.lastUsed.timeIntervalSince1970.isFinite && activity.lastUsed >= .distantPast && activity.lastUsed <= .distantFuture &&
                activityIDs.insert(activity.id).inserted && activityKeys[activity.project.id, default: []].insert(key).inserted
        }) else { throw CocoaError(.coderReadCorrupt) }
        return ledger
    }

    func save(_ ledger: TimesheetLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        defaults.set(data, forKey: key)
    }
}
