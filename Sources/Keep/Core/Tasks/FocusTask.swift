import Foundation

struct FocusTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isComplete = false
    /// Only projected habit rows carry an origin; they are never saved as ordinary tasks.
    var habitID: UUID?

    init(id: UUID = UUID(), title: String, isComplete: Bool = false, habitID: UUID? = nil) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        self.habitID = habitID
    }

    var listID: String { habitID.map { "habit/" + $0.uuidString } ?? "task/" + id.uuidString }

    static let examples = [
        FocusTask(title: "Plan today's priorities", isComplete: true),
        FocusTask(title: "Read a chapter"),
        FocusTask(title: "Make progress on a personal project")
    ]
}
