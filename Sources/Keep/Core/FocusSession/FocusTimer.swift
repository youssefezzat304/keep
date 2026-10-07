import Foundation

/// Timing truth is independent of the UI refresh schedule and wall-clock changes.
struct FocusTimer {
    enum Mode {
        case pomodoro
        case flow
    }

    enum Phase: Equatable {
        case idle
        case running
        case stopped
        case completed
    }

    enum Interval {
        case focus
        case rest
    }

    struct Completion {
        let id: UUID
        let interval: Interval
        let duration: TimeInterval
    }

    let mode: Mode
    private(set) var intervalID = UUID()
    private(set) var focusDuration: TimeInterval
    private(set) var breakDuration: TimeInterval
    private(set) var shortBreakDuration: TimeInterval
    private(set) var longBreakDuration: TimeInterval
    private(set) var iterationsBeforeLongBreak: Int
    private(set) var completedFocusIntervals = 0
    private(set) var isLongBreak = false
    private var nextFocusDuration: TimeInterval
    private var accumulated: TimeInterval = 0
    private var startedAt: ContinuousClock.Instant?
    private var storedPhase: Phase = .idle
    private(set) var interval: Interval = .focus
    var intervalDuration: TimeInterval { interval == .focus ? focusDuration : breakDuration }
    var nextBreakIsLong: Bool { breakIsLong() }
    var nextBreakDuration: TimeInterval { upcomingBreakDuration() }

    func breakIsLong(at instant: ContinuousClock.Instant = .now) -> Bool {
        let pending = interval == .focus && storedPhase != .completed && phase(at: instant) == .completed ? 1 : 0
        return completedFocusIntervals + pending >= iterationsBeforeLongBreak
    }

    func upcomingBreakDuration(at instant: ContinuousClock.Instant = .now) -> TimeInterval {
        breakIsLong(at: instant) ? longBreakDuration : shortBreakDuration
    }

    init(mode: Mode, focusDuration: TimeInterval = 25 * 60, breakDuration: TimeInterval = 5 * 60, longBreakDuration: TimeInterval = 15 * 60, iterationsBeforeLongBreak: Int = 4) {
        precondition(focusDuration > 0 && focusDuration.isFinite)
        precondition(breakDuration > 0 && breakDuration.isFinite)
        precondition(longBreakDuration > 0 && longBreakDuration.isFinite && iterationsBeforeLongBreak > 0)
        self.mode = mode
        self.focusDuration = focusDuration
        self.breakDuration = breakDuration
        self.shortBreakDuration = breakDuration
        self.longBreakDuration = longBreakDuration
        self.iterationsBeforeLongBreak = iterationsBeforeLongBreak
        nextFocusDuration = focusDuration
    }

    func elapsed(at instant: ContinuousClock.Instant = .now) -> TimeInterval {
        guard let startedAt else { return accumulated }
        let duration = (instant - startedAt).components
        let interval = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        return accumulated + max(0, interval)
    }

    func phase(at instant: ContinuousClock.Instant = .now) -> Phase {
        if mode == .pomodoro && elapsed(at: instant) >= intervalDuration {
            return .completed
        }
        return storedPhase
    }

    func seconds(at instant: ContinuousClock.Instant = .now) -> Int {
        switch mode {
        case .pomodoro: Int(ceil(max(0, intervalDuration - elapsed(at: instant))))
        case .flow: Int(floor(elapsed(at: instant)))
        }
    }

    func display(at instant: ContinuousClock.Instant = .now) -> String {
        let seconds = seconds(at: instant)
        switch mode {
        case .pomodoro:
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        case .flow:
            return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
    }

    mutating func play(at instant: ContinuousClock.Instant = .now) {
        settleCompletion(at: instant)
        guard phase(at: instant) != .running else { return }
        if phase(at: instant) == .completed { prepareFocus() }
        startedAt = instant
        storedPhase = .running
    }

    /// Task-row Focus starts focus even during a break, without clearing completed cycle progress.
    mutating func playFocus(at instant: ContinuousClock.Instant = .now) {
        settleCompletion(at: instant)
        if interval == .rest { prepareFocus() }
        play(at: instant)
    }

    /// Stop preserves elapsed time so Play can continue. Reset starts a new session.
    mutating func stop(at instant: ContinuousClock.Instant = .now) {
        settleCompletion(at: instant)
        guard storedPhase == .running else { return }
        accumulated = elapsed(at: instant)
        if mode == .pomodoro { accumulated = min(accumulated, intervalDuration) }
        startedAt = nil
        storedPhase = .stopped
    }

    mutating func reset() {
        completedFocusIntervals = 0
        prepareFocus()
    }

    private mutating func prepareFocus() {
        intervalID = UUID()
        interval = .focus
        isLongBreak = false
        focusDuration = nextFocusDuration
        breakDuration = shortBreakDuration
        accumulated = 0
        startedAt = nil
        storedPhase = .idle
    }

    mutating func startBreak(at instant: ContinuousClock.Instant = .now) {
        settleCompletion(at: instant)
        guard mode == .pomodoro, interval == .focus, phase(at: instant) == .completed else { return }
        isLongBreak = nextBreakIsLong
        breakDuration = nextBreakDuration
        if isLongBreak { completedFocusIntervals = 0 }
        accumulated = 0
        interval = .rest
        startedAt = instant
        storedPhase = .running
    }

    /// Count each completed focus interval once, even if refreshes arrive late.
    @discardableResult
    mutating func settleCompletion(at instant: ContinuousClock.Instant = .now) -> Completion? {
        guard mode == .pomodoro, storedPhase != .completed, phase(at: instant) == .completed else { return nil }
        accumulated = intervalDuration
        startedAt = nil
        storedPhase = .completed
        if interval == .focus { completedFocusIntervals += 1 }
        return Completion(id: intervalID, interval: interval, duration: intervalDuration)
    }

    /// Active/paused intervals keep their original duration; new intervals use these settings.
    mutating func configure(_ settings: PomodoroSettings, at instant: ContinuousClock.Instant = .now) {
        guard mode == .pomodoro, settings.isValid else { return }
        settleCompletion(at: instant)
        nextFocusDuration = Double(settings.focusMinutes * 60)
        shortBreakDuration = Double(settings.shortBreakMinutes * 60)
        longBreakDuration = Double(settings.longBreakMinutes * 60)
        iterationsBeforeLongBreak = settings.iterationsBeforeLongBreak
        if storedPhase == .idle { prepareFocus() }
    }
}
