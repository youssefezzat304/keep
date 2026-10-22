import SwiftUI

struct TimesheetDaySessions: View {
    let workspace: WorkspaceModel
    let project: FocusProject
    let day: TimesheetDay
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Selection?
    private enum Selection: Identifiable {
        case block(CalendarProjectBlock), session(RecordedSession), add
        var id: String {
            switch self {
            case .block(let block): "block/" + block.id
            case .session(let session): "session/" + session.id
            case .add: "add"
            }
        }
    }
    private var projection: TimesheetDayProjection { .init(projectID: project.id, dayID: day.id, index: workspace.readIndex) }
    private var canAdd: Bool {
        workspace.canTrack && day.id <= TaskDay.id(for: .now, calendar: workspace.calendar) &&
        (project.id == FocusProject.unassigned.id || workspace.projects.contains { $0.id == project.id })
    }

    var body: some View {
        let projection = projection
        VStack(alignment: .leading, spacing: 18) {
            Text(project.name).font(KeepTheme.headingFont(size: 26)).fixedSize(horizontal: false, vertical: true)
            Text(day.date, format: Date.FormatStyle(date: .complete, time: .omitted, calendar: workspace.calendar, timeZone: workspace.calendar.timeZone))
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            HStack {
                Text("Calendar blocks").font(.system(size: 14, weight: .medium))
                Spacer()
                Text(TimesheetDuration.clock(projection.recorded)).monospacedDigit()
            }
            if projection.blocks.isEmpty {
                Text("No recorded blocks for this project on this day.")
                    .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                KeepScrollView {
                    VStack(spacing: 10) {
                        ForEach(projection.blocks) { block in
                            Button {
                                if block.sessions.count == 1, let session = block.sessions.first { selection = .session(session) }
                                else { selection = .block(block) }
                            } label: { blockRow(block) }
                                .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                                .accessibilityLabel("Edit block, \(block.startTime) to \(block.endTime), \(block.sessions.count) entries")
                        }
                    }
                }.frame(height: min(340, CGFloat(projection.blocks.count) * 106))
            }
            if abs(projection.adjustment) >= 0.5 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Saved untimed adjustment")
                        Spacer()
                        Text((projection.adjustment < 0 ? "−" : "+") + TimesheetDuration.clock(abs(projection.adjustment))).monospacedDigit()
                    }.font(.system(size: 12, weight: .medium))
                    Text("Kept from an earlier daily total edit. It has no start or end time.")
                        .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                }.padding(12).background(KeepTheme.mutedWarm.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text("Day total").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(TimesheetDuration.clock(projection.total)).monospacedDigit()
            }
            HStack {
                Button { selection = .add } label: { Label("Add entry", systemImage: "plus") }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary)).disabled(!canAdd)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 460)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
        .sheet(item: $selection) { selected in
            switch selected {
            case .session(let session): CalendarSessionDetail(workspace: workspace, selectedSession: session)
            case .block(let block): CalendarBlockEntries(block: block, workspace: workspace) { selection = .session($0) }
            case .add: CalendarEntryDialog(workspace: workspace, initialDate: day.date, initialProjectID: project.id)
            }
        }
    }

    private func blockRow(_ block: CalendarProjectBlock) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(block.project.accentColor).frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(block.titles.joined(separator: " · ")).font(.system(size: 14, weight: .medium)).lineLimit(2)
                Text("\(block.startTime) – \(block.endTime)").font(.system(size: 12)).monospacedDigit()
                if block.sessions.count > 1 {
                    Text("\(block.sessions.count) entries\(block.gaps.isEmpty ? "" : " · gaps excluded")")
                        .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(TimesheetDuration.clock(block.seconds)).font(.system(size: 13, weight: .medium)).monospacedDigit()
            Image(systemName: "pencil").accessibilityHidden(true)
        }.frame(minHeight: 76).padding(.vertical, 6)
    }
}
