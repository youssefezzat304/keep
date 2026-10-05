import SwiftUI

struct ActiveTargetHeader: View {
    @Binding var taskName: String
    @Binding var selectedProject: FocusProject?
    var isCompact = false
    @State private var showsProjectPicker = false
    @State private var projectButtonHovered = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case project, task
    }

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
            Button { showsProjectPicker = true } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                .foregroundStyle(KeepTheme.accentStrong)
                .frame(width: 46, height: 44)
                .background(KeepTheme.background.opacity(projectButtonHovered ? 0.85 : 0.5), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .onHover { projectButtonHovered = $0 }
            .focused($focusedField, equals: .project)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focusedField == .project ? KeepTheme.focusRing : .clear, lineWidth: 2)
            }
            .accessibilityLabel("Select project. Current project: \(selectedProject?.name ?? "No project")")
            .help("Select a project")
            .popover(isPresented: $showsProjectPicker) {
                ProjectPicker(projects: FocusProject.defaults, selectedProject: selectedProject) { project in
                    selectedProject = project
                    showsProjectPicker = false
                    focusedField = .task
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
                    .foregroundStyle(KeepTheme.secondaryInk)
                    .lineLimit(1)
                    .help(selectedProject?.name ?? "No project")
                TextField("Task name", text: $taskName, prompt: Text("Name a task…").foregroundColor(KeepTheme.mutedInk))
                    .font(.system(size: 14, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .task)
                    .accessibilityLabel("Task name")
                    .onSubmit { focusedField = nil }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(focusedField != nil || showsProjectPicker ? KeepTheme.focusRing : KeepTheme.border, lineWidth: focusedField != nil || showsProjectPicker ? 2 : 1)
        }
    }
}

#Preview {
    ActiveTargetHeader(taskName: .constant("Your next good idea"), selectedProject: .constant(FocusProject.defaults.first))
        .padding().background(KeepTheme.paper).preferredColorScheme(.light)
}

#Preview("No project") {
    ActiveTargetHeader(taskName: .constant(""), selectedProject: .constant(nil))
        .padding().background(KeepTheme.paper).preferredColorScheme(.light)
}
