import SwiftUI

struct ActiveTargetHeader: View {
    @Bindable var editor: FocusTaskEditor
    let workspace: WorkspaceModel
    var isCompact = false
    @Environment(\.self) private var environment
    @State private var showsProjectPicker = false
    @State private var showsProjectCreation = false
    @State private var showsTaskPicker = false
    @State private var projectButtonHovered = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case project, task, startBoth
    }

    private var selectedProject: FocusProject? { workspace.selectedProject }
    private var projectColor: Color { selectedProject?.labelColor(in: environment) ?? KeepTheme.mutedInk }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                heading
                Spacer(minLength: 16)
                targetField
            }
            VStack(alignment: .leading, spacing: 16) {
                heading
                targetField
            }
        }
        .foregroundStyle(KeepTheme.ink)
        .onChange(of: focusedField) { _, field in
            if editor.isEditing && field != .task && !showsTaskPicker { finishEditing() }
        }
        .onChange(of: editor.isEditing) { _, editing in
            if !editing { showsTaskPicker = false; focusedField = nil }
        }
        .onChange(of: showsTaskPicker) { _, presented in
            if !presented { finishEditing() }
        }
        .onDisappear { finishEditing() }
        .sheet(isPresented: $showsProjectCreation, onDismiss: { focusedField = nil }) {
            ProjectCreationDialog { name, accent in
                let project = try workspace.createProject(name: name, accent: accent)
                workspace.selectProject(project)
            }
        }
    }

    private func finishEditing() {
        editor.commit(to: workspace)
        focusedField = nil
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("A little space to focus.")
                .font(KeepTheme.headingFont(size: isCompact ? 30 : 36, weight: .regular))
                .fixedSize(horizontal: true, vertical: false)
            Text("One thing at a time. At your own pace.")
                .font(.system(size: 14))
                .foregroundStyle(KeepTheme.mutedInk)
        }
    }

    private var targetField: some View {
        HStack(spacing: 12) {
            Button { finishEditing(); showsProjectPicker = true } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(projectColor)
                    .frame(width: 46, height: 44)
                    .background((selectedProject?.accentColor ?? KeepTheme.mutedWarm).opacity(projectButtonHovered ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .onHover { projectButtonHovered = $0 }
            .focused($focusedField, equals: .project)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focusedField == .project ? KeepTheme.focusRing : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("Select project. Current project: \(selectedProject?.name ?? "No project")")
            .help("Select a project")
            .popover(isPresented: $showsProjectPicker) {
                ProjectPicker(projects: workspace.projects, selectedProject: selectedProject, onCreate: workspace.canTrack ? {
                    showsProjectPicker = false
                    showsProjectCreation = true
                } : nil) { project in
                    workspace.selectProject(project)
                    showsProjectPicker = false
                    focusedField = nil
                }
                .onExitCommand { showsProjectPicker = false }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("WORKING ON")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(KeepTheme.mutedInk)
                Text(selectedProject?.name ?? "No project")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(projectColor)
                    .lineLimit(1)
                    .help(selectedProject?.name ?? "No project")
                Button {
                    showsTaskPicker = true
                    editor.begin(in: workspace)
                } label: {
                    HStack {
                        Text(workspace.taskName.isEmpty ? "Your next good idea" : workspace.taskName)
                            .font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedField, equals: .task)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(focusedField == .task ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false)
                }
                .accessibilityLabel("Select or name a task")
                .accessibilityValue(workspace.taskName.isEmpty ? "No task name" : workspace.taskName)
                .help("Choose a recent task or name a new one")
                .popover(isPresented: $showsTaskPicker) {
                    TaskSuggestionPicker(editor: editor, workspace: workspace, onSubmit: {
                        finishEditing()
                        showsTaskPicker = false
                    }, onSelect: { activity in
                        editor.cancel()
                        workspace.selectTask(activity)
                        showsTaskPicker = false
                    }, onCancel: {
                        editor.cancel()
                        showsTaskPicker = false
                    })
                }
            }

            startBothButton
        }
        .padding(14)
        .frame(width: 450)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var startBothButton: some View {
        let bothRunning = workspace.bothTimersRunning(at: workspace.displayInstant)
        let isBreak = workspace.pomodoro.interval == .rest
        return Button {
            finishEditing()
            if bothRunning { workspace.stopBothTimers() }
            else { workspace.startBothTimers() }
        } label: {
            Label(bothRunning ? "Stop both" : isBreak ? "Start focus + flow" : "Start both",
                  systemImage: bothRunning ? "stop.fill" : "play.fill")
                .fixedSize()
        }
        .buttonStyle(KeepButtonStyle(emphasis: .quiet))
        .focused($focusedField, equals: .startBoth)
        .disabled(!workspace.canTrack)
        .accessibilityLabel(bothRunning ? "Stop both timers" : isBreak ? "End the Pomodoro break and start focus and flow" : "Start or resume both timers")
        .help(bothRunning ? "Stop both timers and keep their current time" : "Start or resume focus and flow without resetting running timers. Flow records overlapping time once.")
    }
}

#Preview {
    ActiveTargetHeader(editor: FocusTaskEditor(), workspace: WorkspaceModel())
        .padding().background(KeepTheme.paper).preferredColorScheme(.light)
}

#Preview("No project") {
    let workspace = WorkspaceModel()
    workspace.selectProject(nil)
    return ActiveTargetHeader(editor: FocusTaskEditor(), workspace: workspace)
        .padding().background(KeepTheme.paper).preferredColorScheme(.light)
}
