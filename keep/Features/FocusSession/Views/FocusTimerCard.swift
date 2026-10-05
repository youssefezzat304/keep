import SwiftUI

struct FocusTimerCard: View {
    @Binding var timer: FocusTimer
    @FocusState private var resetFocused: Bool

    private var isPomodoro: Bool { timer.mode == .pomodoro }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: timer.phase() != .running)) { _ in
            let instant = ContinuousClock.now
            let phase = timer.phase(at: instant)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(isPomodoro ? "Pomodoro" : "Flow state")
                            .font(.system(size: 25, weight: .regular, design: .serif))
                        Text(isPomodoro ? "A little focus, a little rest." : "Find your rhythm. Stay a while.")
                            .font(.system(size: 13))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isPomodoro ? "timer" : "leaf")
                        .font(.system(size: 22, weight: .light))
                        .frame(width: 46, height: 46)
                        .background(KeepTheme.paper.opacity(0.45), in: Circle())
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.display(at: instant))
                        .font(.system(size: 72, weight: .light))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityLabel(isPomodoro ? "Pomodoro time remaining" : "Flow time elapsed")
                        .accessibilityValue(timer.display(at: instant))

                    HStack(spacing: 6) {
                        Circle().fill(KeepTheme.ink)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text(status(for: phase))
                            .font(.system(size: 12))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 104, alignment: .leading)

                HStack(spacing: 10) {
                    PrimaryButton(
                        buttonTitle: phase == .running ? "Stop" : phase == .stopped ? "Continue" : "Play",
                        systemImage: phase == .running ? "stop.fill" : "play.fill"
                    ) {
                        if phase == .running { timer.stop() } else { timer.play() }
                    }
                    .accessibilityLabel("\(phase == .running ? "Stop" : "Play") \(isPomodoro ? "Pomodoro" : "flow timer")")
                    .help(phase == .running ? "Stop and keep the current time" : "Start or continue this timer")

                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40)
                            .background(KeepTheme.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .focused($resetFocused)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(resetFocused ? KeepTheme.focusRing : .clear, lineWidth: 2)
                            .padding(-3)
                    }
                    .disabled(phase == .idle)
                    .opacity(phase == .idle ? 0.55 : 1)
                    .accessibilityLabel("Reset \(isPomodoro ? "Pomodoro" : "flow timer")")
                    .help(isPomodoro ? "Reset to 25 minutes" : "Reset elapsed time to zero")

                    Spacer(minLength: 0)
                    Text(isPomodoro ? "25 MIN" : "NO LIMIT")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.4)
                }
            }
            .foregroundStyle(KeepTheme.ink)
            .cardStyle(backgroundColor: isPomodoro ? KeepTheme.accent : KeepTheme.sage)
            .onChange(of: phase) { _, newPhase in
                if newPhase == .completed { timer.stop(at: instant) }
            }
        }
    }

    private func status(for phase: FocusTimer.Phase) -> String {
        switch phase {
        case .idle: "Ready when you are"
        case .running: isPomodoro ? "One thing at a time" : "In your own time"
        case .stopped: "Stopped · continue whenever you're ready"
        case .completed: "Nicely done. Time for a breather."
        }
    }
}
