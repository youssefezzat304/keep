import SwiftUI

struct TimesheetView: View {
    let workspace: WorkspaceModel
    @State private var weekOffset = 0
    @State private var showsProjectPicker = false
    @State private var showsProjectCreation = false

    private var week: TimesheetWeek {
        let date = workspace.calendar.date(byAdding: .weekOfYear, value: weekOffset, to: workspace.today) ?? workspace.today
        return TimesheetWeek(containing: date, calendar: workspace.calendar)
    }
    private var projects: [FocusProject] { workspace.ledger.projects(dayIDs: week.dayIDs) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    heading
                    Spacer(minLength: 16)
                    recordingLabel
                }
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    recordingLabel
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    weekPicker
                    Spacer(minLength: 12)
                    weekSummary
                }
                VStack(alignment: .leading, spacing: 16) {
                    weekPicker
                    weekSummary
                }
            }

            TimesheetTable(workspace: workspace, week: week)

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
                if weekOffset != 0 {
                    Button("This week") { weekOffset = 0 }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text("Click any time to edit · h:mm:ss")
                Spacer()
                Text("A week of small steps.")
            }
            .font(.system(size: 11))
            .foregroundStyle(KeepTheme.mutedInk)
        }
        .foregroundStyle(KeepTheme.ink)
        .sheet(isPresented: $showsProjectCreation) {
            ProjectCreationDialog { name, accent in
                let project = try workspace.createProject(name: name, accent: accent)
                workspace.addProject(project, on: week.days.first?.date ?? workspace.today)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Your week, at a glance.")
                .font(.system(size: 36, weight: .regular, design: .serif))
                .fixedSize(horizontal: true, vertical: false)
            Text("Time spent across your projects, Monday to Sunday.")
                .font(.system(size: 14))
                .foregroundStyle(KeepTheme.mutedInk)
        }
    }

    private var recordingLabel: some View {
        Label(workspace.isRecording() ? "Recording time" : "Recorded time", systemImage: workspace.isRecording() ? "record.circle" : "clock")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(KeepTheme.highlight.opacity(0.6), in: Capsule())
    }

    private var weekPicker: some View {
        HStack(spacing: 12) {
            weekArrow("chevron.left", label: "Previous week", offset: -1)
            Image(systemName: "calendar")
                .foregroundStyle(KeepTheme.accentStrong)
                .accessibilityHidden(true)
            Text(week.range)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
            Text(week.number)
                .font(.system(size: 10, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(KeepTheme.mutedInk)
            weekArrow("chevron.right", label: "Next week", offset: 1)
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var weekSummary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("WEEK TOTAL")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(KeepTheme.mutedInk)
                Text("\(projects.count) \(projects.count == 1 ? "project" : "projects")")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepTheme.mutedInk)
            }
            Text(TimesheetDuration.total(workspace.ledger.total(dayIDs: week.dayIDs)))
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(KeepTheme.accentStrong)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func weekArrow(_ symbol: String, label: String, offset: Int) -> some View {
        Button { weekOffset += offset } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    TimesheetView(workspace: TimesheetPreviewData.workspace())
        .padding(24).frame(width: 1000).background(KeepTheme.paper)
}
