import Foundation

/// In-memory sample projects for the focus picker, independent of timesheet fixtures.
struct FocusProject: Identifiable, Equatable {
    enum Accent {
        case terracotta, sage, mistBlue, butter
    }

    let id: String
    let name: String
    let accent: Accent

    static let examples = [
        FocusProject(id: "keep", name: "Keep", accent: .terracotta),
        FocusProject(id: "german", name: "Learning German", accent: .sage),
        FocusProject(id: "website", name: "Website refresh", accent: .mistBlue),
        FocusProject(id: "reading", name: "Reading & research", accent: .butter)
    ]
}
