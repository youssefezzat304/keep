import Foundation

/// Explicitly labeled visual-draft fixtures; never written to the live Timesheet ledger.
struct DashboardCalendarSample: Identifiable {
    let id: Int
    let day: Int
    let startMinute: Int
    let endMinute: Int
    let project: FocusProject
    let task: String
    var seconds: TimeInterval { Double((endMinute - startMinute) * 60) }
}

enum DashboardCalendarSamples {
    static let sessions: [DashboardCalendarSample] = [
        .init(id: 1, day: 0, startMinute: 9 * 60, endMinute: 10 * 60 + 30, project: FocusProject.defaults[0], task: "Shape the next good idea"),
        .init(id: 2, day: 0, startMinute: 11 * 60, endMinute: 12 * 60, project: FocusProject.defaults[1], task: "A little language practice"),
        .init(id: 3, day: 0, startMinute: 14 * 60, endMinute: 15 * 60 + 30, project: FocusProject.defaults[2], task: "Sketch a fresh direction"),
        .init(id: 4, day: 1, startMinute: 9 * 60 + 30, endMinute: 11 * 60, project: FocusProject.defaults[2], task: "Make room for the details"),
        .init(id: 5, day: 1, startMinute: 13 * 60, endMinute: 14 * 60, project: FocusProject.defaults[3], task: "Read, reflect, repeat"),
        .init(id: 6, day: 2, startMinute: 10 * 60, endMinute: 12 * 60, project: FocusProject.defaults[0], task: "Build something small"),
        .init(id: 7, day: 2, startMinute: 14 * 60, endMinute: 15 * 60, project: FocusProject.defaults[1], task: "Words for the everyday"),
        .init(id: 8, day: 3, startMinute: 9 * 60, endMinute: 11 * 60, project: FocusProject.defaults[2], task: "Bring it all together"),
        .init(id: 9, day: 3, startMinute: 13 * 60 + 30, endMinute: 15 * 60, project: FocusProject.defaults[0], task: "One thoughtful improvement"),
        .init(id: 10, day: 4, startMinute: 10 * 60, endMinute: 11 * 60 + 30, project: FocusProject.defaults[0], task: "Finish with a little care"),
        .init(id: 11, day: 4, startMinute: 14 * 60, endMinute: 15 * 60, project: FocusProject.defaults[3], task: "Follow your curiosity"),
        .init(id: 12, day: 5, startMinute: 11 * 60, endMinute: 12 * 60, project: FocusProject.defaults[3], task: "A slow morning chapter")
    ]
    static var total: TimeInterval { sessions.reduce(0) { $0 + $1.seconds } }
    static func total(on day: Int) -> TimeInterval { sessions.filter { $0.day == day }.reduce(0) { $0 + $1.seconds } }
}
