import SwiftUI

struct TimerWorkspaceCard: View {
    let workspace: WorkspaceModel
    var isCompact = false
    var beforeAction: () -> Void = {}

    var body: some View {
        if isCompact {
            VStack(spacing: 18) { panels }
        } else {
            HStack(alignment: .top, spacing: 18) { panels }
        }
    }

    @ViewBuilder private var panels: some View {
        PomodoroTimerPanel(workspace: workspace, beforeAction: beforeAction)
        FlowTimerPanel(workspace: workspace, beforeAction: beforeAction)
    }
}

#Preview {
    TimerWorkspaceCard(workspace: WorkspaceModel())
    .padding().frame(width: 900)
}
