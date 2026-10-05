import SwiftUI

struct FlowTimerPanel: View {
    let workspace: WorkspaceModel

    var body: some View {
        FocusTimerCard(
            timer: workspace.flow,
            canPlay: workspace.canTrack,
            flowOverrides: workspace.flow.phase() == .running,
            onPlay: { workspace.play(.flow) },
            onStop: { workspace.stop(.flow) },
            onReset: { workspace.reset(.flow) },
            onBreak: { workspace.startBreak() }
        )
    }
}

#Preview {
    FlowTimerPanel(workspace: WorkspaceModel())
        .padding().frame(width: 450)
}
