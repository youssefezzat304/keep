import SwiftUI

struct TimesheetTable: View {
    let workspace: WorkspaceModel
    let week: TimesheetWeek
    @Environment(\.self) private var environment
    private let projectWidth: CGFloat = 205
    private let totalWidth: CGFloat = 100
    private let removeWidth: CGFloat = 44
    private let headerHeight: CGFloat = 68
    private let rowHeight: CGFloat = 78
    private let totalHeight: CGFloat = 64

    private var projects: [FocusProject] { workspace.ledger.projects(dayIDs: week.dayIDs) }

    var body: some View {
        GeometryReader { geometry in
            let tableWidth = max(900, geometry.size.width)
            let dayWidth = (tableWidth - projectWidth - totalWidth - removeWidth - 32) / 7

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header(dayWidth: dayWidth)
                    divider
                    ForEach(projects) { project in
                        projectRow(project, dayWidth: dayWidth)
                        divider
                    }
                    if projects.isEmpty {
                        VStack(spacing: 9) {
                            Text("A fresh week of focus.").font(.system(size: 22, design: .serif))
                            Text("Choose a project and start a timer, or add a project to enter time.")
                                .font(.system(size: 13))
                                .foregroundStyle(KeepTheme.mutedInk)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 130)
                    }
                    totals(dayWidth: dayWidth)
                }
                .padding(.horizontal, 16)
                .frame(width: tableWidth)
            }
            .scrollIndicators(.visible)
        }
        .frame(height: headerHeight + rowHeight * CGFloat(projects.count) + totalHeight + CGFloat(projects.count + 1) + (projects.isEmpty ? 130 : 0))
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Weekly timesheet. Click a time to edit hours, minutes, and seconds. Scroll horizontally for all seven days on smaller windows.")
    }

    private func header(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("PROJECT")
                    .tracking(1.3)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(KeepTheme.mutedInk)
            .frame(width: projectWidth, alignment: .leading)

            ForEach(week.days) { day in
                VStack(spacing: 5) {
                    Text(day.label)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(KeepTheme.mutedInk)
                    Text(day.number)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                }
                .frame(width: dayWidth, height: headerHeight)
                .background { Rectangle().fill(day.isWeekend ? KeepTheme.paper : .clear) }
                .accessibilityElement(children: .combine)
            }

            Text("TOTAL")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(KeepTheme.mutedInk)
                .frame(width: totalWidth, height: headerHeight, alignment: .trailing)
            Color.clear.frame(width: removeWidth)
        }
        .frame(height: headerHeight)
    }

    private func projectRow(_ project: FocusProject, dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(project.accentColor)
                    .frame(width: 12, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(project.labelColor(in: environment))
                        .lineLimit(1)
                    Text(project.category)
                        .font(.system(size: 11))
                        .foregroundStyle(KeepTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            .frame(width: projectWidth, alignment: .leading)

            ForEach(week.days) { day in
                TimesheetTimeCell(
                    seconds: workspace.ledger.seconds(projectID: project.id, dayID: day.id),
                    projectName: project.name,
                    day: day,
                    color: project.accentColor,
                    canEdit: workspace.canTrack
                ) { seconds in
                    workspace.edit(seconds: seconds, project: project, dayID: day.id)
                }
                .frame(width: dayWidth - 16)
                .frame(width: dayWidth, height: rowHeight)
                .background { Rectangle().fill(day.isWeekend ? KeepTheme.paper : .clear) }
            }

            Text(TimesheetDuration.total(workspace.ledger.total(dayIDs: week.dayIDs, projectID: project.id)))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .frame(width: totalWidth, alignment: .trailing)
                .accessibilityLabel("\(project.name) total: \(TimesheetDuration.clock(workspace.ledger.total(dayIDs: week.dayIDs, projectID: project.id)))")
            RemoveRowButton(label: "Remove \(project.name)'s time for this week") {
                workspace.removeTimesheetProject(project, dayIDs: week.dayIDs)
            }
            .disabled(!workspace.canTrack)
            .frame(width: removeWidth)
        }
        .frame(height: rowHeight)
    }

    private func totals(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("DAILY TOTAL")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(KeepTheme.secondaryInk)
                .frame(width: projectWidth, alignment: .leading)

            ForEach(week.days) { day in
                Text(TimesheetDuration.clock(workspace.ledger.total(dayIDs: [day.id])))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(width: dayWidth, height: totalHeight)
                    .background { Rectangle().fill(day.isWeekend ? KeepTheme.mutedWarm.opacity(0.28) : .clear) }
                    .accessibilityLabel("\(day.label) total: \(TimesheetDuration.clock(workspace.ledger.total(dayIDs: [day.id])))")
            }

            Text(TimesheetDuration.total(workspace.ledger.total(dayIDs: week.dayIDs)))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(KeepTheme.accentStrong)
                .frame(width: totalWidth, alignment: .trailing)
                .accessibilityLabel("Week total: \(TimesheetDuration.clock(workspace.ledger.total(dayIDs: week.dayIDs)))")
            Color.clear.frame(width: removeWidth)
        }
        .frame(height: totalHeight)
        .background { Rectangle().fill(KeepTheme.paper) }
    }

    private var divider: some View {
        Rectangle().fill(KeepTheme.border).frame(height: 1)
    }
}

#Preview {
    TimesheetTable(workspace: WorkspaceModel(), week: TimesheetWeek(containing: .now))
        .padding().frame(width: 950).background(KeepTheme.paper)
}
