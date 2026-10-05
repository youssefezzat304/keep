import SwiftUI

struct FocusSessionView: View {
    @Bindable var workspace: WorkspaceModel
    var isCompact = false
    var minimumHeight: CGFloat = 0
    @State private var taskName = "Your next good idea"
    @State private var tasks = FocusTask.examples

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ActiveTargetHeader(taskName: $taskName, workspace: workspace, isCompact: isCompact)

            TimerWorkspaceCard(workspace: workspace, isCompact: isCompact)

            if isCompact {
                VStack(spacing: 18) { supportingCards }
            } else {
                HStack(alignment: .top, spacing: 18) { supportingCards }
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .foregroundStyle(KeepTheme.accentStrong)
                    .accessibilityHidden(true)
                Text("Less hurry. More here.")
                Spacer()
                Text(Date.now, format: .dateTime.month(.wide).day())
            }
            .font(.system(size: 12))
            .foregroundStyle(KeepTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
    }

    @ViewBuilder private var supportingCards: some View {
        MusicPlayerCard()
        TasksCard(tasks: $tasks)
    }
}

#Preview {
    FocusSessionView(workspace: WorkspaceModel())
        .padding().frame(width: 950).background(KeepTheme.paper)
}
