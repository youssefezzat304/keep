import SwiftUI

struct DashboardProjectsView: View {
    let workspace: WorkspaceModel
    @Environment(\.self) private var environment
    @State private var showsCreation = false
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
                    Text("A fresh place to begin.").font(.system(size: 24, design: .serif))
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
                                RemoveRowButton(label: "Delete project: \(project.name)") { deletion = project }
                                    .disabled(!workspace.canTrack)
                            }
                            .foregroundStyle(project.labelColor(in: environment))
                            .padding(.horizontal, 20).frame(height: 64)
                            separator
                        }
                    }
                }.accessibilityLabel("Projects")
            }
            separator
            Button { showsCreation = true } label: {
                Label("Add project", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            .disabled(!workspace.canTrack).padding(12)
        }
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
        .sheet(isPresented: $showsCreation) {
            ProjectCreationDialog { name, accent in _ = try workspace.createProject(name: name, accent: accent) }
        }
        .alert("Delete project?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("Cancel", role: .cancel) { deletion = nil }
            Button("Delete project", role: .destructive) {
                if let project = deletion { workspace.deleteProject(project) }
                deletion = nil
            }
        } message: {
            Text("Remove \(deletion?.name ?? "this project") from your project list? Recorded time stays in Timesheet and Calendar. If this project is selected, running timers continue under No project.")
        }
    }

    private var separator: some View { Divider().overlay(KeepTheme.border).allowsHitTesting(false) }
}

#Preview("Projects") {
    DashboardView(workspace: WorkspaceModel(), initialPage: .projects)
        .padding(24).frame(width: 1000, height: 820).background(KeepTheme.paper)
}
