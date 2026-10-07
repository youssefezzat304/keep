import SwiftUI

struct FocusTimerCard: View {
    let timer: FocusTimer
    var canPlay = true
    var flowOverrides = false
    let onPlay: () -> Void
    let onStop: () -> Void
    let onReset: () -> Void
    let onBreak: () -> Void
    var pomodoroSettings: PomodoroSettings = .defaults
    var onSettings: ((PomodoroSettings) -> Bool)? = nil
    @Environment(\.self) private var environment
    @State private var showsSettings = false
    @State private var settingsHovered = false
    @FocusState private var settingsFocused: Bool
    @FocusState private var resetFocused: Bool
    @FocusState private var breakFocused: Bool

    private var isPomodoro: Bool { timer.mode == .pomodoro }
    private var isBreak: Bool { isPomodoro && timer.interval == .rest }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: timer.phase() != .running)) { _ in
            let instant = ContinuousClock.now
            let phase = timer.phase(at: instant)
            let longBreakDue = timer.breakIsLong(at: instant)
            let upcomingBreakDuration = timer.upcomingBreakDuration(at: instant)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(isPomodoro ? "Pomodoro" : "Flow state")
                            .font(KeepTheme.headingFont(size: 25, weight: .regular))
                        Text(isBreak ? "Take a little breather." : isPomodoro ? "A little focus, a little rest." : "Find your rhythm. Stay a while.")
                            .font(.system(size: 13))
                    }
                    Spacer(minLength: 8)
                    if isPomodoro {
                        Button { showsSettings = true } label: {
                            timerIcon
                                .background(KeepTheme.paper.opacity(settingsHovered ? 0.65 : 0.45), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { settingsHovered = $0 }
                        .focused($settingsFocused)
                        .overlay { Circle().strokeBorder(settingsFocused || showsSettings ? KeepTheme.focusRing : .clear, lineWidth: 2) }
                        .disabled(!canPlay || onSettings == nil)
                        .accessibilityLabel("Pomodoro settings")
                        .help("Set focus and break durations")
                        .popover(isPresented: $showsSettings) {
                            PomodoroSettingsPopover(settings: pomodoroSettings) { onSettings?($0) ?? false }
                        }
                    } else {
                        timerIcon.background(KeepTheme.paper.opacity(0.45), in: Circle()).accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.display(at: instant))
                        .font(.system(size: 72, weight: .light))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityLabel(isBreak ? "Break time remaining" : isPomodoro ? "Pomodoro time remaining" : "Flow time elapsed")
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

                ViewThatFits(in: .horizontal) {
                    controlRow(phase: phase, longBreakDue: longBreakDue, upcomingBreakDuration: upcomingBreakDuration, includeBreak: true)
                    VStack(alignment: .leading, spacing: 12) {
                        controlRow(phase: phase, longBreakDue: longBreakDue, upcomingBreakDuration: upcomingBreakDuration, includeBreak: false)
                        if isPomodoro && !isBreak && phase == .completed {
                            breakControl(longBreakDue: longBreakDue, upcomingBreakDuration: upcomingBreakDuration)
                        }
                    }
                }
            }
            .foregroundStyle(KeepTheme.ink)
            .cardStyle(backgroundColor: surfaceColor)
        }
    }

    private var surfaceColor: Color {
        KeepTheme.timerSurface(mode: timer.mode, isBreak: isBreak, environment: environment)
    }

    private func controlRow(phase: FocusTimer.Phase, longBreakDue: Bool, upcomingBreakDuration: TimeInterval, includeBreak: Bool) -> some View {
        HStack(spacing: 10) {
            PrimaryButton(
                buttonTitle: phase == .running ? "Stop" : phase == .stopped ? "Continue" : phase == .completed ? "Focus again" : "Play",
                systemImage: phase == .running ? "stop.fill" : "play.fill"
            ) {
                if phase == .running { onStop() } else { onPlay() }
            }
            .disabled(!canPlay)
            .accessibilityLabel(phase == .completed ? "Start a new Pomodoro focus interval" : "\(phase == .running ? "Stop" : "Play") \(isBreak ? "Pomodoro break" : isPomodoro ? "Pomodoro" : "flow timer")")
            .help(phase == .completed ? "Start a new focus interval" : phase == .running ? "Stop and keep the current time" : "Start or continue this timer")

            Button(action: onReset) {
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
            .help(isPomodoro ? "Reset the Pomodoro cycle using your saved focus duration" : "Reset elapsed time to zero")

            if includeBreak && isPomodoro && !isBreak && phase == .completed {
                breakControl(longBreakDue: longBreakDue, upcomingBreakDuration: upcomingBreakDuration)
            }

            Spacer(minLength: 0)
            Text(isBreak ? (timer.isLongBreak ? "LONG BREAK" : "SHORT BREAK") : isPomodoro ? "\(minutes(timer.focusDuration)) MIN" : "NO LIMIT")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.4)
        }
    }

    private func breakControl(longBreakDue: Bool, upcomingBreakDuration: TimeInterval) -> some View {
        Button(action: onBreak) {
            Text("\(minutes(upcomingBreakDuration))m \(longBreakDue ? "long " : "")break")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(KeepTheme.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focused($breakFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(breakFocused ? KeepTheme.focusRing : .clear, lineWidth: 2)
                .padding(-3)
        }
        .disabled(!canPlay)
        .accessibilityLabel("Start a \(minutes(upcomingBreakDuration))-minute \(longBreakDue ? "long" : "short") Pomodoro break")
        .help("Break time is not added to the Pomodoro timesheet")
    }

    private var timerIcon: some View {
        Image(systemName: isBreak ? "cup.and.saucer" : isPomodoro ? "timer" : "leaf")
            .font(.system(size: 22, weight: .light))
            .frame(width: 46, height: 46)
    }

    private func minutes(_ duration: TimeInterval) -> Int { Int((duration / 60).rounded(.up)) }

    private func status(for phase: FocusTimer.Phase) -> String {
        if isBreak { return phase == .completed ? "Break complete · ready for a little focus" : phase == .stopped ? "Break paused · not counted" : "Break time · not counted by Pomodoro" }
        if isPomodoro && phase == .running && flowOverrides { return "Flow is counting this time" }
        return switch phase {
        case .idle: "Ready when you are"
        case .running: isPomodoro ? "One thing at a time" : "In your own time"
        case .stopped: "Stopped · continue whenever you're ready"
        case .completed: timer.nextBreakIsLong ? "Nicely done. Time for a longer breather." : "Nicely done. Time for a breather."
        }
    }
}
