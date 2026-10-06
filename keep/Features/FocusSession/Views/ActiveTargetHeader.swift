import SwiftUI

struct ActiveTargetHeader: View {
    @Bindable var editor: FocusTaskEditor
    let workspace: WorkspaceModel
    var isCompact = false
    @Environment(\.self) private var environment
    @State private var showsProjectPicker = false
    @State private var showsProjectCreation = false
    @State private var projectButtonHovered = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case project, task
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
            if editor.isEditing && field != .task { finishEditing() }
        }
        .onChange(of: editor.isEditing) { _, editing in
            if !editing { focusedField = nil }
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
                .font(.system(size: isCompact ? 30 : 36, weight: .regular, design: .serif))
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
                if editor.isEditing {
                    TextField("Task name", text: $editor.text, prompt: Text("Your next good idea").foregroundColor(KeepTheme.mutedInk))
                        .font(.system(size: 14, weight: .medium))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .task)
                        .accessibilityLabel("Task name")
                        .onSubmit { finishEditing() }
                        .onExitCommand { editor.cancel(); focusedField = nil }
                } else {
                    Button {
                        editor.begin(in: workspace)
                        focusedField = .task
                    } label: {
                        Text(workspace.taskName.isEmpty ? "Your next good idea" : workspace.taskName)
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit task name")
                    .accessibilityValue(workspace.taskName.isEmpty ? "No task name" : workspace.taskName)
                    .help("Click to name your task")
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
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
