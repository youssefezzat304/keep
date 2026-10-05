import Foundation

struct FocusTask: Identifiable {
    let id = UUID()
    var title: String
    var isComplete = false

    static let examples = [
        FocusTask(title: "Plan today's priorities", isComplete: true),
        FocusTask(title: "Read a chapter"),
        FocusTask(title: "Make progress on a personal project")
    ]
}
