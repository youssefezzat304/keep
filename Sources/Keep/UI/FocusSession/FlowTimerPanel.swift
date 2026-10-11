import SwiftUI

struct FlowTimerPanel: View {
    let workspace: WorkspaceModel
    var beforeAction: () -> Void = {}
    var preferences: AppPreferences?

    var body: some View {
        FocusTimerCard(
            timer: workspace.flow,
            canPlay: workspace.canTrack,
            flowOverrides: workspace.flow.phase() == .running,
            onPlay: { beforeAction(); workspace.play(.flow) },
            onStop: { beforeAction(); workspace.stop(.flow) },
            onReset: { beforeAction(); workspace.reset(.flow) },
            onBreak: { beforeAction(); workspace.startBreak() },
            flowReminderMinutes: preferences?.flowReminderMinutes,
            onFlowReminder: preferences.map { preferences in { preferences.setFlowReminder(minutes: $0) } },
            canConfigureReminders: preferences?.canEdit ?? false
        )
    }
}

#Preview {
    FlowTimerPanel(workspace: WorkspaceModel())
        .padding().frame(width: 450)
}
