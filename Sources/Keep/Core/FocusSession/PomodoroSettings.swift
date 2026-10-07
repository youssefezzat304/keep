import Foundation

nonisolated struct PomodoroSettings: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var iterationsBeforeLongBreak = 4

    static let defaults = PomodoroSettings()
    static let focusRange = 1...180
    static let shortBreakRange = 1...60
    static let longBreakRange = 1...120
    static let iterationsRange = 1...12

    var isValid: Bool {
        Self.focusRange.contains(focusMinutes) && Self.shortBreakRange.contains(shortBreakMinutes) &&
        Self.longBreakRange.contains(longBreakMinutes) && Self.iterationsRange.contains(iterationsBeforeLongBreak)
    }
}
