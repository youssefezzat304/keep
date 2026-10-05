import Foundation

/// A standalone, deterministic harness until the app has an Xcode test target.
@main
enum FocusTimerChecks {
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

        print("Passed 24 deterministic timer checks: independent play/stop, resume, reset, completion, delayed refresh, and formatting.")
    }

    private static func expect(_ condition: Bool, _ description: String) {
        precondition(condition, description)
    }
}
