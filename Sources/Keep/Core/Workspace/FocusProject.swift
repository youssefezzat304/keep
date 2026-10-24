import Foundation

/// Shared project catalog for focus selection and recorded timesheet rows.
nonisolated struct FocusProject: Identifiable, Equatable, Codable, Sendable {
    enum Accent: String, Codable, CaseIterable, Sendable {
        case neutral, habits, terracotta, sage, mistBlue, butter
        case rust, clay, apricot, peach, rose, dustyRose, mauve, plum
        case lavender, lilac, periwinkle, denim, slate, teal, seafoam
        case eucalyptus, olive, moss, fern, honey, ochre, sand, taupe, cocoa, walnut, stone

        static var projectColors: [Accent] { allCases.filter { $0 != .neutral && $0 != .habits } }

        var name: String {
            switch self {
            case .mistBlue: "Mist blue"
            case .dustyRose: "Dusty rose"
            default: rawValue.capitalized
            }
        }
    }

    let id: String
    let name: String
    let accent: Accent
    let category: String

    var hourlyRate: ProjectHourlyRate? = nil
    var isHabitsProject: Bool { id == Self.habits.id || accent == .habits }

    static let unassigned = FocusProject(id: "no-project", name: "No project", accent: .neutral, category: "Unassigned time")

    static let habits = FocusProject(id: "habits", name: "Habits", accent: .habits, category: "Habit tracking")

    static let defaults = [
        FocusProject(id: "keep", name: "Keep", accent: .terracotta, category: "Personal project"),
        FocusProject(id: "german", name: "Learning German", accent: .sage, category: "Language learning"),
        FocusProject(id: "website", name: "Website refresh", accent: .mistBlue, category: "Design & development"),
        FocusProject(id: "reading", name: "Reading & research", accent: .butter, category: "A little curiosity"),
        habits
    ]
}

enum ProjectCreationError: LocalizedError {
    case invalidName, duplicateName, unavailable, invalidColor, missing, colorInUse, projectLimit

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a project name with 1–80 characters."
        case .duplicateName: "A project with this name already exists. Choose another name."
        case .unavailable: "Retry loading your saved data before changing projects."
        case .missing: "This project is no longer available. Close this dialog and choose another project."
        case .colorInUse: "This color belongs to another project. Choose an available color."
        case .projectLimit: "All 30 project colors are assigned. Delete a project before creating another."
        case .invalidColor: "Choose one of the project colors."
        }
    }
}
