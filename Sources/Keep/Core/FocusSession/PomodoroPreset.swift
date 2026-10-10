import Foundation

nonisolated struct PomodoroPreset: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let settings: PomodoroSettings

    static let maximumNameLength = 80

    var isValid: Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines) &&
            name.count <= Self.maximumNameLength && settings.isValid
    }

    var nameKey: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    var summary: String {
        "\(settings.focusMinutes)m focus · \(settings.shortBreakMinutes)m short break · \(settings.longBreakMinutes)m long break · every \(settings.iterationsBeforeLongBreak) intervals"
    }
}

enum PomodoroPresetError: LocalizedError {
    case unavailable, invalidName, invalidSettings, duplicateName, missing, saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Retry loading your saved workspace before changing presets."
        case .invalidName: "Name your preset using 1–80 characters."
        case .invalidSettings: "Enter valid focus and break durations before saving a preset."
        case .duplicateName: "A preset already uses this name. Choose a different name."
        case .missing: "This preset was removed. Choose another preset."
        case .saveFailed: "Your changes are in memory. Retry saving in the workspace to keep them after relaunch."
        }
    }
}
