import SwiftUI

struct TimerWorkspaceCard: View {
    let workspace: WorkspaceModel
    var isCompact = false
    var beforeAction: () -> Void = {}
    var preferences: AppPreferences?

    var body: some View {
        if isCompact {
            VStack(spacing: 18) { panels }
        } else {
            HStack(alignment: .top, spacing: 18) { panels }
        }
    }

    @ViewBuilder private var panels: some View {
        if preferences?.showPomodoroTimer != false {
            PomodoroTimerPanel(workspace: workspace, beforeAction: beforeAction,
                showProgress: preferences?.showPomodoroProgress ?? true)
        }
        if preferences?.showFlowTimer != false {
            FlowTimerPanel(workspace: workspace, beforeAction: beforeAction, preferences: preferences)
        }
    }
}

#Preview {
    TimerWorkspaceCard(workspace: WorkspaceModel())
    .padding().frame(width: 900)
}
