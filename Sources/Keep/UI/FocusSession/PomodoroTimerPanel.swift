import SwiftUI

struct PomodoroTimerPanel: View {
    let workspace: WorkspaceModel
    var beforeAction: () -> Void = {}
    var showProgress = true

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
            onSettings: { beforeAction(); return workspace.updatePomodoroSettings($0) },
            pomodoroPresets: workspace.pomodoroPresets,
            onSavePreset: { try workspace.savePomodoroPreset(name: $0, settings: $1) },
            onRemovePreset: { try workspace.removePomodoroPreset(id: $0) },
            showPomodoroProgress: showProgress
        )
    }
}

#Preview {
    PomodoroTimerPanel(workspace: WorkspaceModel())
        .padding().frame(width: 450)
}
