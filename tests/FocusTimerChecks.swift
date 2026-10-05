import Foundation

/// A standalone, deterministic harness until the app has an Xcode test target.
@main
enum FocusTimerChecks {
    static var checks = 0
    @MainActor static func main() {
        let origin = ContinuousClock.now
        var pomodoro = FocusTimer(mode: .pomodoro)
        var flow = FocusTimer(mode: .flow)

        expect(pomodoro.display(at: origin) == "25:00", "Initial Pomodoro display")
        expect(flow.display(at: origin) == "00:00:00", "Initial flow display")
        expect(pomodoro.phase(at: origin) == .idle, "Initial idle state")

        pomodoro.play(at: origin)
        flow.play(at: origin)
        let tenSeconds = origin.advanced(by: .seconds(10))
        expect(pomodoro.display(at: tenSeconds) == "24:50", "Countdown")
        expect(flow.display(at: tenSeconds) == "00:00:10", "Count up")

        pomodoro.stop(at: tenSeconds)
        let later = origin.advanced(by: .seconds(30))
        expect(pomodoro.phase(at: later) == .stopped, "Stopped phase")
        expect(pomodoro.display(at: later) == "24:50", "Stopped timer stays frozen")
        expect(flow.display(at: later) == "00:00:30", "Stopping Pomodoro leaves flow running")

        pomodoro.play(at: later)
        pomodoro.play(at: later.advanced(by: .seconds(1)))
        let fortySeconds = origin.advanced(by: .seconds(40))
        expect(pomodoro.display(at: fortySeconds) == "24:40", "Resume excludes stopped interval and duplicate Play")
        flow.stop(at: fortySeconds)
        expect(pomodoro.display(at: origin.advanced(by: .seconds(50))) == "24:30", "Stopping flow leaves Pomodoro running")
        expect(flow.display(at: origin.advanced(by: .seconds(50))) == "00:00:40", "Flow stop preserves time")

        flow.reset()
        expect(flow.phase(at: fortySeconds) == .idle, "Flow reset state")
        expect(flow.seconds(at: fortySeconds) == 0, "Flow reset time")
        expect(pomodoro.phase(at: fortySeconds) == .running, "Flow reset leaves Pomodoro alone")

        pomodoro.reset()
        expect(pomodoro.seconds(at: fortySeconds) == 1500, "Pomodoro reset duration")
        expect(pomodoro.phase(at: fortySeconds) == .idle, "Pomodoro reset state")
        pomodoro.play(at: origin)
        let completion = origin.advanced(by: .seconds(1501))
        expect(pomodoro.seconds(at: completion) == 0, "Countdown never becomes negative")
        expect(pomodoro.phase(at: completion) == .completed, "Completion derives from elapsed time")
        pomodoro.stop(at: completion)
        expect(pomodoro.phase(at: completion) == .completed, "Stopping a completed interval keeps completion")
        expect(pomodoro.elapsed(at: completion.advanced(by: .seconds(60))) == 1500, "Completed session freezes elapsed time")
        pomodoro.play(at: completion)
        expect(pomodoro.display(at: completion) == "25:00", "Play after completion starts a fresh interval")

        flow.play(at: origin)
        expect(flow.display(at: origin.advanced(by: .seconds(3661))) == "01:01:01", "Flow hours formatting")
        expect(flow.display(at: origin.advanced(by: .milliseconds(999))) == "00:00:00", "Flow floors partial seconds")
        expect(pomodoro.display(at: completion.advanced(by: .milliseconds(1))) == "25:00", "Countdown rounds up partial seconds")

        var cycle = FocusTimer(mode: .pomodoro, focusDuration: 2, breakDuration: 3, longBreakDuration: 7, iterationsBeforeLongBreak: 2)
        cycle.play(at: origin)
        cycle.settleCompletion(at: origin.advanced(by: .seconds(3)))
        cycle.settleCompletion(at: origin.advanced(by: .seconds(4)))
        expect(cycle.completedFocusIntervals == 1, "Repeated completion refresh counts once")
        expect(!cycle.nextBreakIsLong && cycle.nextBreakDuration == 3, "First interval offers a short break")
        cycle.startBreak(at: origin.advanced(by: .seconds(4)))
        expect(cycle.interval == .rest && !cycle.isLongBreak && cycle.intervalDuration == 3, "Short break starts manually")
        cycle.stop(at: origin.advanced(by: .seconds(5)))
        cycle.play(at: origin.advanced(by: .seconds(10)))
        expect(cycle.seconds(at: origin.advanced(by: .seconds(10))) == 2, "Paused short break resumes remaining time")
        cycle.play(at: origin.advanced(by: .seconds(12)))
        expect(cycle.interval == .focus && cycle.completedFocusIntervals == 1, "Focus after short break preserves cycle progress")
        expect(cycle.breakIsLong(at: origin.advanced(by: .seconds(14))) && cycle.upcomingBreakDuration(at: origin.advanced(by: .seconds(14))) == 7, "Upcoming break reflects completion before the next refresh settles it")
        cycle.stop(at: origin.advanced(by: .seconds(14)))
        expect(cycle.completedFocusIntervals == 2 && cycle.nextBreakIsLong, "Threshold offers a long break")
        cycle.startBreak(at: origin.advanced(by: .seconds(14)))
        expect(cycle.isLongBreak && cycle.intervalDuration == 7, "Long break uses its own duration")
        expect(cycle.completedFocusIntervals == 0, "Taking long break starts a new cycle")
        cycle.play(at: origin.advanced(by: .seconds(21)))
        expect(cycle.interval == .focus && !cycle.isLongBreak && cycle.completedFocusIntervals == 0, "Long break completion is not a focus iteration")
        cycle.play(at: origin.advanced(by: .seconds(23)))
        expect(cycle.completedFocusIntervals == 1, "Skipping a break still counts completed focus")
        cycle.play(at: origin.advanced(by: .seconds(25)))
        cycle.stop(at: origin.advanced(by: .seconds(27)))
        expect(cycle.nextBreakIsLong, "Skipping a due long break keeps a long break available")
        cycle.reset()
        expect(cycle.completedFocusIntervals == 0 && cycle.interval == .focus, "Reset restarts the cycle")

        var configured = FocusTimer(mode: .pomodoro)
        let settings = PomodoroSettings(focusMinutes: 10, shortBreakMinutes: 2, longBreakMinutes: 8, iterationsBeforeLongBreak: 1)
        configured.configure(settings, at: origin)
        expect(configured.focusDuration == 600 && configured.display(at: origin) == "10:00", "Idle settings update countdown")
        configured.play(at: origin)
        configured.stop(at: origin.advanced(by: .seconds(30)))
        let changed = PomodoroSettings(focusMinutes: 3, shortBreakMinutes: 4, longBreakMinutes: 12, iterationsBeforeLongBreak: 1)
        configured.configure(changed, at: origin.advanced(by: .seconds(40)))
        expect(configured.focusDuration == 600 && configured.seconds(at: origin.advanced(by: .seconds(40))) == 570, "Paused focus keeps its duration and progress")
        configured.play(at: origin.advanced(by: .seconds(50)))
        configured.startBreak(at: origin.advanced(by: .seconds(620)))
        expect(configured.isLongBreak && configured.breakDuration == 720, "Next break uses updated settings")
        configured.configure(settings, at: origin.advanced(by: .seconds(630)))
        expect(configured.breakDuration == 720 && configured.seconds(at: origin.advanced(by: .seconds(630))) == 710, "Running break keeps its original duration")
        configured.play(at: origin.advanced(by: .seconds(1340)))
        expect(configured.focusDuration == 600, "Next focus uses latest settings")
        configured.reset()
        expect(configured.focusDuration == 600 && configured.completedFocusIntervals == 0, "Reset uses latest settings and clears cycle")
        configured.configure(PomodoroSettings(focusMinutes: 0), at: origin)
        expect(configured.focusDuration == 600, "Invalid settings cannot change timer")
        flow.configure(settings, at: origin)
        expect(flow.mode == .flow && flow.focusDuration == 1500, "Pomodoro configuration leaves Flow alone")

        print("Passed \(checks) deterministic timer checks: independent controls, completion, configurable intervals, and short/long break cycles.")
    }

    private static func expect(_ condition: Bool, _ description: String) {
        checks += 1
        precondition(condition, description)
    }
}
