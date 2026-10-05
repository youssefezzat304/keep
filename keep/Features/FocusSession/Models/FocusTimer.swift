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

    let mode: Mode
    let focusDuration: TimeInterval
    let breakDuration: TimeInterval
    private(set) var interval: Interval = .focus
    var intervalDuration: TimeInterval { interval == .focus ? focusDuration : breakDuration }
    private var accumulated: TimeInterval = 0
    private var startedAt: ContinuousClock.Instant?
    private var storedPhase: Phase = .idle

    init(mode: Mode, focusDuration: TimeInterval = 25 * 60, breakDuration: TimeInterval = 5 * 60) {
        precondition(focusDuration > 0 && focusDuration.isFinite)
        precondition(breakDuration > 0 && breakDuration.isFinite)
        self.mode = mode
        self.focusDuration = focusDuration
        self.breakDuration = breakDuration
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
        guard phase(at: instant) != .running else { return }
        if phase(at: instant) == .completed { reset() }
        startedAt = instant
        storedPhase = .running
    }

    /// Stop preserves elapsed time so Play can continue. Reset starts a new session.
    mutating func stop(at instant: ContinuousClock.Instant = .now) {
        guard storedPhase == .running else { return }
        accumulated = elapsed(at: instant)
        if mode == .pomodoro { accumulated = min(accumulated, intervalDuration) }
        startedAt = nil
        storedPhase = .stopped
    }

    mutating func reset() {
        interval = .focus
        accumulated = 0
        startedAt = nil
        storedPhase = .idle
    }

    mutating func startBreak(at instant: ContinuousClock.Instant = .now) {
        guard mode == .pomodoro, interval == .focus, phase(at: instant) == .completed else { return }
        reset()
        interval = .rest
        startedAt = instant
        storedPhase = .running
    }
}
