import SwiftUI

struct DashboardProjectsView: View {
    let workspace: WorkspaceModel
    @Environment(\.self) private var environment
    @State private var editing: FocusProject?
    @State private var goalProject: FocusProject?
    @State private var deletion: FocusProject?

    private var projects: [FocusProject] {
        workspace.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROJECT").font(.system(size: 12, weight: .medium)).tracking(1.2)
                .foregroundStyle(KeepTheme.mutedInk).padding(20)
            separator
            if projects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A fresh place to begin.").font(KeepTheme.headingFont(size: 24))
                    Text("Add a project to organize your next focus session.")
                        .font(.system(size: 14)).foregroundStyle(KeepTheme.secondaryInk)
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                KeepScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projects) { project in
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill").font(.system(size: 18))
                                    .frame(width: 24).accessibilityHidden(true)
                                Text(project.name).font(.system(size: 16, weight: .medium))
                                    .lineLimit(1).help(project.name)
                                Spacer(minLength: 12)
                                Button { goalProject = project } label: { Label(workspace.projectTargets[project.id] == nil ? "Set goals" : "Goals", systemImage: "target") }
                                    .buttonStyle(KeepButtonStyle(emphasis: workspace.projectTargets[project.id] == nil ? .informational : .success)).disabled(!workspace.canTrack)
                                    .accessibilityLabel("Weekly targets for \(project.name)")
                                Button { editing = project } label: { Image(systemName: "pencil") }
                                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                                    .accessibilityLabel("Edit project: \(project.name)")
                                    .help("Edit project")
                                    .disabled(!workspace.canTrack)
                                if !project.isHabitsProject {
                                    RemoveRowButton(label: "Delete project: \(project.name)", destructive: true) { deletion = project }
                                        .disabled(!workspace.canTrack)
                                }
                            }
                            .foregroundStyle(project.labelColor(in: environment))
                            .padding(.horizontal, 20).frame(height: 64)
                            separator
                        }
                    }
                }.accessibilityLabel("Projects")
            }
        }
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
        .sheet(item: $editing) { project in
            ProjectEditorDialog(project: project, usedColors: Set(workspace.projects.map(\.accent))) { name, accent, rate in
                try workspace.updateProject(project, name: name, accent: accent, hourlyRate: rate)
            }
        }
        .sheet(item: $goalProject) { project in
            ProjectGoalsDialog(workspace: workspace, project: project)
        }
        .sheet(item: $deletion) { project in
            ProjectDeletionDialog(project: project, canDelete: workspace.canTrack) { workspace.deleteProject(project) }
        }
    }

    private var separator: some View { Divider().overlay(KeepTheme.border).allowsHitTesting(false) }
}

#Preview("Projects") {
    DashboardView(workspace: WorkspaceModel(), initialPage: .projects)
        .padding(24).frame(width: 1000, height: 820).background(KeepTheme.paper)
}
