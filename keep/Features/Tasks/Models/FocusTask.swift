import Foundation

struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isComplete = false

    init(id: UUID = UUID(), title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
    }

    static let examples = [
        FocusTask(title: "Plan today's priorities", isComplete: true),
        FocusTask(title: "Read a chapter"),
        FocusTask(title: "Make progress on a personal project")
    ]
}
