import SwiftUI

struct PomodoroTimerPanel: View {
    let workspace: WorkspaceModel

    var body: some View {
        FocusTimerCard(
            timer: workspace.pomodoro,
            canPlay: workspace.canTrack,
            flowOverrides: workspace.flow.phase() == .running,
            onPlay: { workspace.play(.pomodoro) },
            onStop: { workspace.stop(.pomodoro) },
            onReset: { workspace.reset(.pomodoro) },
            onBreak: { workspace.startBreak() }
        )
    }
}

#Preview {
    PomodoroTimerPanel(workspace: WorkspaceModel())
        .padding().frame(width: 450)
}
