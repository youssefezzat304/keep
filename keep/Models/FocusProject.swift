import Foundation

/// Shared project catalog for focus selection and recorded timesheet rows.
struct FocusProject: Identifiable, Equatable, Codable {
    enum Accent: String, Codable, CaseIterable {
        case neutral, terracotta, sage, mistBlue, butter
        case rust, clay, apricot, peach, rose, dustyRose, mauve, plum
        case lavender, lilac, periwinkle, denim, slate, teal, seafoam
        case eucalyptus, olive, moss, fern, honey, ochre, sand, taupe, cocoa, walnut, stone

        static var projectColors: [Accent] { allCases.filter { $0 != .neutral } }

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

    static let unassigned = FocusProject(id: "no-project", name: "No project", accent: .neutral, category: "Unassigned time")

    static let defaults = [
        FocusProject(id: "keep", name: "Keep", accent: .terracotta, category: "Personal project"),
        FocusProject(id: "german", name: "Learning German", accent: .sage, category: "Language learning"),
        FocusProject(id: "website", name: "Website refresh", accent: .mistBlue, category: "Design & development"),
        FocusProject(id: "reading", name: "Reading & research", accent: .butter, category: "A little curiosity")
    ]
}

enum ProjectCreationError: LocalizedError {
    case invalidName, duplicateName, unavailable, invalidColor

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a project name with 1–80 characters."
        case .duplicateName: "A project with this name already exists. Choose another name."
        case .unavailable: "Retry loading your saved data before creating a project."
        case .invalidColor: "Choose one of the project colors."
        }
    }
}
