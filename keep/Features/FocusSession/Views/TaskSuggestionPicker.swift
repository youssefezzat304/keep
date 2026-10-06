import SwiftUI

struct TaskSuggestionPicker: View {
    @Bindable var editor: FocusTaskEditor
    let workspace: WorkspaceModel
    let onSubmit: () -> Void
    let onSelect: (TaskActivity) -> Void
    let onCancel: () -> Void
    @Environment(\.self) private var environment
    @FocusState private var searchFocused: Bool

    private var matches: [TaskActivity] {
        let query = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspace.taskSuggestions.filter {
            query.isEmpty || editor.text == workspace.taskName || $0.title.localizedStandardContains(query) || $0.project.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("What are you working on?", text: $editor.text)
                .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                .padding(12).background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: 1).allowsHitTesting(false) }
                .focused($searchFocused).onSubmit(onSubmit)
                .accessibilityLabel("Task name or search recent tasks")
            if matches.isEmpty {
                Text(workspace.taskSuggestions.isEmpty ? "Tasks you use with a timer will appear here." : "No matching tasks. Press Return to use this name.")
                    .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            } else {
                KeepScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach([true, false], id: \.self) { pinned in
                            let activities = matches.filter { $0.isPinned == pinned }
                            if !activities.isEmpty {
                                Text(pinned ? "PINNED" : "RECENT ACTIVITY")
                                    .font(.system(size: 10, weight: .medium)).tracking(1.2)
                                    .foregroundStyle(KeepTheme.mutedInk).padding(.top, 8).padding(.horizontal, 10)
                                ForEach(activities) { activity in row(activity) }
                            }
                        }
                    }
                }.frame(maxHeight: 300)
            }
        }
        .padding(16).frame(width: 380)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.surface)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private func row(_ activity: TaskActivity) -> some View {
        HStack(spacing: 4) {
            Button { onSelect(activity) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Label(activity.project.name, systemImage: "folder.fill")
                        .font(.system(size: 11)).foregroundStyle(activity.project.labelColor(in: environment)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            .accessibilityLabel("Select task \(activity.title), project \(activity.project.name)")
            Button { workspace.toggleTaskPin(activity) } label: {
                Image(systemName: activity.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            .help(activity.isPinned ? "Unpin task" : "Pin task")
            .accessibilityLabel("\(activity.isPinned ? "Unpin" : "Pin") task \(activity.title), project \(activity.project.name)")
            .disabled(!workspace.canTrack)
        }
    }
}
