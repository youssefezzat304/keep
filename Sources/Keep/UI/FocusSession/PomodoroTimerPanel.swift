import SwiftUI

struct PomodoroTimerPanel: View {
    let workspace: WorkspaceModel
    var beforeAction: () -> Void = {}

    var body: some View {
        FocusTimerCard(
            timer: workspace.pomodoro,
            canPlay: workspace.canTrack,
            flowOverrides: workspace.flow.phase() == .running,
            onPlay: { beforeAction(); workspace.play(.pomodoro) },
            onStop: { beforeAction(); workspace.stop(.pomodoro) },
            onReset: { beforeAction(); workspace.reset(.pomodoro) },
            onBreak: { beforeAction(); workspace.startBreak() },
            pomodoroSettings: workspace.pomodoroSettings,
            onSettings: { beforeAction(); return workspace.updatePomodoroSettings($0) }
        )
    }
}

#Preview {
    PomodoroTimerPanel(workspace: WorkspaceModel())
        .padding().frame(width: 450)
}
