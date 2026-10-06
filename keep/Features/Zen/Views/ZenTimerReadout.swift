import SwiftUI

struct ZenTimerReadout: View {
    let workspace: WorkspaceModel
    let mode: FocusTimer.Mode
    private var timer: FocusTimer { mode == .pomodoro ? workspace.pomodoro : workspace.flow }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: timer.phase() != .running)) { _ in
            let instant = ContinuousClock.now
            let phase = timer.phase(at: instant)
            VStack(alignment: .leading, spacing: 5) {
                Text(title(phase: phase))
                    .font(.system(size: 10, weight: .medium)).tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 8) {
                    Text(timer.display(at: instant))
                        .font(.system(size: 32, weight: .light)).monospacedDigit().lineLimit(1)
                        .accessibilityLabel(mode == .flow ? "Flow time elapsed" : timer.interval == .rest ? "Break time remaining" : "Focus time remaining")
                        .accessibilityValue(timer.display(at: instant))
                    Button {
                        if phase == .running { workspace.stop(mode) }
                        else { workspace.play(mode) }
                    } label: {
                        Image(systemName: phase == .running ? "pause.fill" : "play.fill").frame(width: 32, height: 32)
                    }
                    .buttonStyle(ZenControlStyle()).disabled(!workspace.canTrack)
                    .accessibilityLabel("\(phase == .running ? "Pause" : "Start or continue") \(mode == .flow ? "Flow" : "Pomodoro")")
                    .help(phase == .running ? "Pause this timer" : "Start or continue this timer")
                }
            }
            .foregroundStyle(.white).shadow(color: .black.opacity(0.65), radius: 3, y: 1)
            .contextMenu {
                Button("Reset timer") { workspace.reset(mode) }.disabled(phase == .idle)
                if mode == .pomodoro, timer.interval == .focus, phase == .completed {
                    Button("Start break") { workspace.startBreak() }.disabled(!workspace.canTrack)
                }
            }
        }
    }

    private func title(phase: FocusTimer.Phase) -> String {
        let name = mode == .flow ? "FLOW" : timer.interval == .rest ? "BREAK" : "FOCUS"
        return name + (phase == .stopped ? " · PAUSED" : phase == .completed ? " · COMPLETE" : "")
    }
}
