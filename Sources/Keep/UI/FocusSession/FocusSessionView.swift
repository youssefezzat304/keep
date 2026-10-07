import SwiftUI

struct FocusSessionView: View {
    @Bindable var workspace: WorkspaceModel
    var music = MusicPlayerModel()
    var tasks = DailyTaskStore()
    var preferences = AppPreferences()
    var wallpapers = WallpaperLibrary()
    var isCompact = false
    var isActive = true
    var minimumHeight: CGFloat = 0
    var onEnterZen: (() -> Void)? = nil
    @State private var taskEditor = FocusTaskEditor()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ActiveTargetHeader(editor: taskEditor, workspace: workspace, isCompact: isCompact)

            TimerWorkspaceCard(workspace: workspace, isCompact: isCompact, beforeAction: { taskEditor.commit(to: workspace) })

            if isCompact {
                VStack(spacing: 18) { supportingCards }
            } else {
                HStack(alignment: .top, spacing: 18) { supportingCards }
            }

            HStack(spacing: 6) {
                Spacer()
                Text(Date.now, format: .dateTime.month(.wide).day())
            }
            .font(.system(size: 12))
            .foregroundStyle(KeepTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .onChange(of: isActive) { _, active in
            if !active { taskEditor.commit(to: workspace) }
        }
    }

    @ViewBuilder private var supportingCards: some View {
        MusicPlayerCard(player: music, preferences: preferences, wallpapers: wallpapers, onEnterZen: onEnterZen.map { enter in { taskEditor.commit(to: workspace); enter() } }, wallpaperIsActive: isActive)
        TasksCard(store: tasks, today: workspace.today, canStartTimer: workspace.canTrack) { task, timers in
            taskEditor.commit(to: workspace)
            workspace.startTask(task.title, timers: timers)
        }
    }
}

#Preview {
    FocusSessionView(workspace: WorkspaceModel())
        .padding().frame(width: 950).background(KeepTheme.paper)
}
