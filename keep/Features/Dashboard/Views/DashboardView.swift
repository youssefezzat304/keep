import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case timesheet, calendar, projects
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .timesheet: "tablecells"
        case .calendar: "calendar"
        case .projects: "folder"
        }
    }
}

/// A shared browsed week and mounted Timesheet, Calendar, and Projects viewports.
struct DashboardView: View {
    let workspace: WorkspaceModel
    @State private var page: DashboardPage
    @State private var weekOffset = 0

    init(workspace: WorkspaceModel, initialPage: DashboardPage = .timesheet) {
        self.workspace = workspace
        _page = State(initialValue: initialPage)
    }

    private var week: TimesheetWeek {
        let date = workspace.calendar.date(byAdding: .weekOfYear, value: weekOffset, to: workspace.today) ?? workspace.today
        return TimesheetWeek(containing: date, calendar: workspace.calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading
                    Spacer(minLength: 12)
                    status
                }
                VStack(alignment: .leading, spacing: 12) { heading; status }
            }
            if page == .projects {
                HStack { Spacer(minLength: 0); pagePicker }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        weekPicker
                        weekSummary
                        Spacer(minLength: 0)
                        pagePicker
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            weekPicker
                            Spacer(minLength: 8)
                            weekSummary
                        }
                        pagePicker
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                KeepScrollView {
                    TimesheetView(workspace: workspace, week: week)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 4)
                }
                // Ignoring inactive children also keeps nested native scroll controls out of the AX tree.
                .accessibilityElement(children: page == .timesheet ? .contain : .ignore)
                .opacity(page == .timesheet ? 1 : 0)
                .allowsHitTesting(page == .timesheet)
                .accessibilityHidden(page != .timesheet)

                DashboardCalendarView(week: week, workspace: workspace)
                    .accessibilityElement(children: page == .calendar ? .contain : .ignore)
                    .opacity(page == .calendar ? 1 : 0)
                    .allowsHitTesting(page == .calendar)
                    .accessibilityHidden(page != .calendar)

                DashboardProjectsView(workspace: workspace)
                    .accessibilityElement(children: page == .projects ? .contain : .ignore)
                    .opacity(page == .projects ? 1 : 0)
                    .allowsHitTesting(page == .projects)
                    .accessibilityHidden(page != .projects)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(page == .projects ? "Your projects." : "Your week, at a glance.")
                .font(.system(size: 36, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text(page == .projects ? "A place for each thing you’re working on." : page == .timesheet ? "Time spent across your projects, Monday to Sunday." : "A little room for everything you’re working on.")
                .font(.system(size: 14)).foregroundStyle(KeepTheme.mutedInk)
        }
    }

    private var status: some View {
        Label(page == .projects ? "\(workspace.projects.count) projects" : workspace.isRecording() ? "Recording time" : "Recorded time",
              systemImage: page == .projects ? "folder" : workspace.isRecording() ? "record.circle" : "clock")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(KeepTheme.highlight.opacity(0.6), in: Capsule())
            .fixedSize()
    }

    private var pagePicker: some View {
        HStack(spacing: 4) {
            ForEach(DashboardPage.allCases) { destination in
                Button { page = destination } label: {
                    Label(destination.title, systemImage: destination.symbol)
                }
                .buttonStyle(KeepButtonStyle(emphasis: page == destination ? .primary : .quiet))
                .accessibilityLabel("Dashboard \(destination.title)")
                .accessibilityAddTraits(page == destination ? .isSelected : [])
            }
        }
        .padding(4)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(KeepTheme.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard view")
    }

    private var weekPicker: some View {
        HStack(spacing: 10) {
            weekArrow("chevron.left", label: "Previous week", offset: -1)
            Image(systemName: "calendar").foregroundStyle(KeepTheme.accentStrong).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(week.range).font(.system(size: 13, weight: .medium))
                Text(week.number).font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
            }
            weekArrow("chevron.right", label: "Next week", offset: 1)
            if weekOffset != 0 {
                Button { weekOffset = 0 } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet)).accessibilityLabel("This week").help("Return to this week")
            }
        }
        .padding(.horizontal, 8).frame(height: 48)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(KeepTheme.border, lineWidth: 1) }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(page == .calendar ? "SESSION TIME" : "WEEK TOTAL")
                .font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(KeepTheme.mutedInk)
            Text(TimesheetDuration.total(page == .calendar ? workspace.ledger.sessions.filter { week.dayIDs.contains($0.dayID) }.reduce(0) { $0 + $1.seconds } : workspace.ledger.total(dayIDs: week.dayIDs)))
                .font(.system(size: 25, design: .serif)).foregroundStyle(KeepTheme.accentStrong).monospacedDigit()
            let count = page == .calendar ? Set(workspace.ledger.sessions.filter { week.dayIDs.contains($0.dayID) }.map { $0.project.id }).count : workspace.ledger.projects(dayIDs: week.dayIDs).count
            Text("\(count) \(count == 1 ? "project" : "projects")")
                .font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
        }
        .fixedSize().accessibilityElement(children: .combine)
    }

    private func weekArrow(_ symbol: String, label: String, offset: Int) -> some View {
        Button { weekOffset += offset } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 24, height: 32)
        }
        .buttonStyle(KeepButtonStyle(emphasis: .quiet))
        .accessibilityLabel(label).help(label)
    }
}

#Preview("Dashboard calendar") {
    DashboardView(workspace: TimesheetPreviewData.workspace(), initialPage: .calendar)
        .padding(24).frame(width: 1000, height: 820).background(KeepTheme.paper)
}
