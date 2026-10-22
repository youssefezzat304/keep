import Foundation

nonisolated enum DashboardPage: String, Codable, CaseIterable, Identifiable {
    case timesheet, calendar, projects
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .timesheet: "tablecells"
        case .calendar: "calendar"
        case .projects: "folder"
        }
    }
}

