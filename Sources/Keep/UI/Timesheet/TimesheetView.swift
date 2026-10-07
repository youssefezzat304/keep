import SwiftUI

struct TimesheetView: View {
    let workspace: WorkspaceModel
    let week: TimesheetWeek
    let projection: WeeklyProjection
    @State private var showsProjectPicker = false
    @State private var showsProjectCreation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TimesheetTable(workspace: workspace, week: week, projection: projection)

            HStack {
                Button { showsProjectPicker = true } label: {
                    Label("Add project", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(KeepTheme.accentStrong)
                .disabled(!workspace.canTrack)
                .help("Add a project to this week and enter time")
                .popover(isPresented: $showsProjectPicker) {
                    ProjectPicker(projects: workspace.projects, selectedProject: nil, onCreate: {
                        showsProjectPicker = false
                        showsProjectCreation = true
                    }) { project in
                        workspace.addProject(project ?? .unassigned, on: week.days.first?.date ?? workspace.today)
                        showsProjectPicker = false
                    }
                }
                Spacer()
            }

            if let removal = workspace.lastTimesheetRemoval {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Removed \(removal.project.name)'s row.")
                        if workspace.isRecording(), (workspace.selectedProject ?? .unassigned).id == removal.project.id,
                           removal.entries.contains(where: { $0.dayID == TimesheetWeek.dayID(for: workspace.today, calendar: workspace.calendar) }) {
                            Text("Running timers continue recording new time.")
                                .foregroundStyle(KeepTheme.mutedInk)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Undo") { workspace.undoTimesheetRemoval() }
                        .disabled(!workspace.canTrack)
                }
                .font(.system(size: 12))
                .padding(12)
                .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text("Click any time to edit · h:mm:ss")
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(KeepTheme.mutedInk)
        }
        .foregroundStyle(KeepTheme.ink)
        .sheet(isPresented: $showsProjectCreation) {
            ProjectEditorDialog(usedColors: Set(workspace.projects.map(\.accent))) { name, accent in
                let project = try workspace.createProject(name: name, accent: accent)
                workspace.addProject(project, on: week.days.first?.date ?? workspace.today)
            }
        }
    }
}

#Preview {
    let workspace = TimesheetPreviewData.workspace()
    let week = TimesheetWeek(containing: .now)
    TimesheetView(workspace: workspace, week: week, projection: WeeklyProjection(days: week.dayIDs, index: workspace.readIndex))
        .padding(24).frame(width: 1000).background(KeepTheme.paper)
}
