import SwiftUI

struct FlowTimerPanel: View {
    let workspace: WorkspaceModel
    var beforeAction: () -> Void = {}
    var presentation: WorkspaceCardPresentation = .standard

    var body: some View {
        FocusTimerCard(
            timer: workspace.flow,
            canPlay: workspace.canTrack,
            flowOverrides: workspace.flow.phase() == .running,
            onPlay: { beforeAction(); workspace.play(.flow) },
            onStop: { beforeAction(); workspace.stop(.flow) },
            onReset: { beforeAction(); workspace.reset(.flow) },
            onBreak: { beforeAction(); workspace.startBreak() },
            presentation: presentation
        )
    }
}

#Preview {
    FlowTimerPanel(workspace: WorkspaceModel())
        .padding().frame(width: 450)
}
