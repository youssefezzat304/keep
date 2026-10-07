import Foundation

/// Numeric fixtures for previews only; the application opens the locally saved ledger.
enum TimesheetPreviewData {
    static func workspace() -> WorkspaceModel {
        let calendar = Calendar.autoupdatingCurrent
        let week = TimesheetWeek(containing: .now, calendar: calendar)
        let minutes = [
            [135, 90, 180, 165, 75, 0, 0],
            [45, 60, 30, 75, 45, 30, 0],
            [90, 0, 120, 60, 150, 0, 0],
            [30, 45, 0, 30, 45, 60, 30]
        ]
        var ledger = TimesheetLedger()
        for (index, project) in FocusProject.defaults.enumerated() {
            for (dayIndex, day) in week.days.enumerated() where minutes[index][dayIndex] > 0 {
                ledger.setSeconds(Double(minutes[index][dayIndex] * 60), project: project, dayID: day.id)
            }
        }
        return WorkspaceModel(ledger: ledger, calendar: calendar)
    }
}
