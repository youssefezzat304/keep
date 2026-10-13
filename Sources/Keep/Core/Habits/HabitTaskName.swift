import Foundation

/// The habit keeps its identity; the optional detail belongs only to its focus target.
nonisolated enum HabitTaskName {
    static func normalizedExtension(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func title(_ name: String, extension detail: String?) -> String {
        guard let detail = detail.flatMap(normalizedExtension) else { return name }
        return name + " - " + detail
    }
}

nonisolated enum HabitTaskNameError: LocalizedError {
    case unavailable, changedHabit, tooLong
    var errorDescription: String? {
        switch self {
        case .unavailable: "Saved habits are unavailable. Retry loading them before editing."
        case .changedHabit: "The active habit changed. Close the editor and choose the habit again."
        case .tooLong: "Keep the habit name and extension within 200 characters."
        }
    }
}
