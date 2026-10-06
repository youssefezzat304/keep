import SwiftUI

struct MenuBarTargetPicker: View {
    @Bindable var editor: FocusTaskEditor
    let workspace: WorkspaceModel
    let isVisible: Bool
    let onBack: () -> Void
    let onSubmit: () -> Void
    let onSelectProject: (FocusProject?) -> Void
    let onSelectTask: (TaskActivity) -> Void
    @Environment(\.self) private var environment
    @FocusState private var nameFocused: Bool

    private var query: String {
        editor.text == workspace.taskName ? "" : editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var projects: [FocusProject] {
        workspace.projects.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var recentTasks: [TaskActivity] {
        workspace.taskSuggestions.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.project.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .accessibilityLabel("Back to focus controls")
                Spacer()
                Text("Working on").font(KeepTheme.headingFont(size: 20))
            }
            TextField("Name a task or search…", text: $editor.text)
                .modifier(KeepInputStyle()).focused($nameFocused)
                .accessibilityLabel("Task name or search projects and recent tasks")
                .onSubmit(submit)
                .disabled(!workspace.canTrack)
            Button("Use task name", action: submit)
                .buttonStyle(KeepButtonStyle(emphasis: .secondary))
                .disabled(editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workspace.canTrack)

            KeepScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    heading("Projects")
                    projectRow(nil)
                    ForEach(projects) { project in projectRow(project) }
                    if projects.isEmpty { helper("No matching projects.") }
                    Divider().overlay(KeepTheme.border).padding(.vertical, 10)
                    heading("Recent tasks")
                    ForEach(recentTasks) { task in
                        Button { onSelectTask(task) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Label(task.project.name, systemImage: "folder.fill")
                                        .font(.system(size: 11)).foregroundStyle(task.project.labelColor(in: environment))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if task.isPinned { Image(systemName: "pin.fill").font(.system(size: 11)).accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        }
                        .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                        .accessibilityLabel("Select task \(task.title), project \(task.project.name)")
                    }
                    if recentTasks.isEmpty {
                        helper(workspace.taskSuggestions.isEmpty ? "Tasks you use with a timer will appear here." : "No matching recent tasks.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
            .disabled(!workspace.canTrack)
        }
        .padding(20)
        .foregroundStyle(KeepTheme.ink)
        .onChange(of: isVisible, initial: true) { _, visible in nameFocused = visible }
        .onExitCommand { if isVisible { onBack() } }
    }

    private func projectRow(_ project: FocusProject?) -> some View {
        let selected = workspace.selectedProject?.id == project?.id
        return Button { onSelectProject(project) } label: {
            HStack(spacing: 10) {
                Label(project?.name ?? "No project", systemImage: "folder.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(project?.labelColor(in: environment) ?? KeepTheme.mutedInk)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11)).accessibilityHidden(true) }
            }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .buttonStyle(KeepButtonStyle(emphasis: .quiet))
        .accessibilityLabel("Select project \(project?.name ?? "No project")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(KeepTheme.headingFont(size: 18)).padding(.vertical, 4)
    }

    private func helper(_ message: String) -> some View {
        Text(message).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
    }

    private func submit() {
        guard workspace.canTrack, !editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmit()
    }
}
