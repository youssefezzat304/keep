import Foundation

/// Prepared once per affected week. Manual totals never become Calendar sessions.
struct WeeklyProjection {
    var projects: [FocusProject] = []
    var sessionsByDay: [String: [RecordedSession]] = [:]
    var sessionDayTotals: [String: Double] = [:]
    var cells: [String: Double] = [:]
    var rowTotals: [String: Double] = [:]
    var dayTotals: [String: Double] = [:]
    var total = 0.0
    var sessionTotal = 0.0
    var sessionProjectCount = 0
    var hasSessions: Bool { sessionProjectCount > 0 }
    func seconds(projectID: String, dayID: String) -> Double { cells["\(projectID)/\(dayID)", default: 0] }

    init() {}
    init(days: [String], index: WorkspaceReadIndex) {
        var catalog: [String: FocusProject] = [:], sessionProjects: Set<String> = []
        for day in days {
            let sessions = index.sessions(on: day)
            sessionsByDay[day] = sessions
            let recorded = TimesheetProjectionRules.recordedSeconds(sessions)
            sessionDayTotals[day] = recorded; sessionTotal += recorded
            sessionProjects.formUnion(sessions.map { $0.project.id })
        }
        // Match the ledger's first saved metadata, including older snapshots of a project.
        for entry in index.entries(on: days) {
            if catalog[entry.project.id] == nil { catalog[entry.project.id] = entry.project }
            cells[entry.id] = entry.seconds
            rowTotals[entry.project.id, default: 0] += entry.seconds
            dayTotals[entry.dayID, default: 0] += entry.seconds
            total += entry.seconds
        }
        projects = catalog.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        sessionProjectCount = sessionProjects.count
    }
}
