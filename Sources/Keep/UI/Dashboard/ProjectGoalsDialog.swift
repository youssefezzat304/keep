import SwiftUI

struct ProjectGoalsDialog: View {
    let workspace: WorkspaceModel
    let project: FocusProject
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var goal: String
    @State private var minimum: String
    @State private var error: String?

    init(workspace: WorkspaceModel, project: FocusProject) {
        self.workspace = workspace; self.project = project
        let saved = workspace.projectTargets[project.id]
        _enabled = State(initialValue: saved != nil)
        _goal = State(initialValue: saved.map { WeeklyTargets.hoursText($0.goal) } ?? "10")
        _minimum = State(initialValue: saved.map { WeeklyTargets.hoursText($0.minimum) } ?? "2")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Weekly project targets").font(KeepTheme.headingFont(size: 26))
            Text(project.name).font(.system(size: 15, weight: .medium))
            WeeklyTargetsFields(enabled: $enabled, goal: $goal, minimum: $minimum, unit: "hours", maximum: "168")
            Text("Progress uses recorded focus, Monday to Sunday. Manual Timesheet adjustments stay separate.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(KeepButtonStyle(emphasis: .quiet))
                Spacer()
                Button("Save") {
                    do {
                        let value = enabled ? try WeeklyTargets.parse(goal: goal, minimum: minimum, hours: true, maximum: WeeklyTargets.maximumMinutes) : nil
                        try workspace.updateProjectTargets(projectID: project.id, targets: value)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(KeepButtonStyle(emphasis: .primary)).disabled(!workspace.canTrack)
            }
        }.padding(24).frame(width: 430).foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
}

