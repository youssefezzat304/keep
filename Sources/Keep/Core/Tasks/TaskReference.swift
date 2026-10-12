import Foundation

/// A daily task keeps its planned date; a habit's occurrence follows the recorded civil day.
nonisolated enum TaskReference: Codable, Hashable, Sendable {
    case task(id: UUID, dayID: String)
    case habit(id: UUID)

    var id: UUID { switch self { case .task(let id, _), .habit(let id): id } }
    var storageKey: String {
        switch self {
        case .task(let id, let day): "task/\(id.uuidString)/\(day)"
        case .habit(let id): "habit/\(id.uuidString)"
        }
    }
    var isValid: Bool { if case .task(_, let day) = self { return TaskDay.isValid(day) }; return true }
    func occurrence(on recordedDay: String) -> TaskFocusKey {
        switch self {
        case .task(let id, let day): .init(kind: .task, id: id, dayID: day)
        case .habit(let id): .init(kind: .habit, id: id, dayID: recordedDay)
        }
    }
}

nonisolated struct TaskFocusKey: Hashable, Sendable {
    enum Kind: String, Sendable { case task, habit }
    let kind: Kind
    let id: UUID
    let dayID: String
}

/// Seconds are derived from sessions, with replacement/removal deltas applied by the read index.
nonisolated struct TaskTimeTotals: Sendable {
    private(set) var habits: [UUID: [String: Double]] = [:]
    private(set) var seconds: [TaskFocusKey: Double] = [:]
    init(sessions: [RecordedSession] = []) { for session in sessions { adjust(session, multiplier: 1) } }
    mutating func adjust(_ session: RecordedSession, multiplier: Double) {
        guard let reference = session.taskReference else { return }
        let key = reference.occurrence(on: session.dayID)
        let value = seconds[key, default: 0] + session.seconds * multiplier
        seconds[key] = value > 0.000001 ? value : nil
        if key.kind == .habit {
            habits[key.id, default: [:]][key.dayID] = value > 0.000001 ? value : nil
            if habits[key.id]?.isEmpty == true { habits[key.id] = nil }
        }
    }
    func focused(_ reference: TaskReference, on day: String) -> Double { seconds[reference.occurrence(on: day), default: 0] }
    static func minutesLabel(seconds: Double) -> String {
        seconds > 0 && seconds < 60 ? "<1 min" : "\(Int(max(0, seconds) / 60)) min"
    }
}

nonisolated enum TaskEditError: LocalizedError {
    case unavailable, missing, invalid
    var errorDescription: String? {
        switch self {
        case .unavailable: "Saved tasks are unavailable. Retry loading them before editing."
        case .missing: "This task was removed. Close the editor and choose another task."
        case .invalid: "Enter a task name and a whole estimate from 1 to 1,440 minutes, or leave the estimate blank."
        }
    }
}
