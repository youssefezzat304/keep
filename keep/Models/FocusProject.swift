import Foundation

/// Shared project catalog for focus selection and recorded timesheet rows.
struct FocusProject: Identifiable, Equatable, Codable {
    enum Accent: String, Codable {
        case neutral, terracotta, sage, mistBlue, butter
    }

    let id: String
    let name: String
    let accent: Accent
    let category: String

    static let unassigned = FocusProject(id: "no-project", name: "No project", accent: .neutral, category: "Unassigned time")

    static let defaults = [
        FocusProject(id: "keep", name: "Keep", accent: .terracotta, category: "Personal project"),
        FocusProject(id: "german", name: "Learning German", accent: .sage, category: "Language learning"),
        FocusProject(id: "website", name: "Website refresh", accent: .mistBlue, category: "Design & development"),
        FocusProject(id: "reading", name: "Reading & research", accent: .butter, category: "A little curiosity")
    ]
}
