import SwiftUI

struct DashboardCalendarView: View {
    let week: TimesheetWeek
    let workspace: WorkspaceModel
    let projection: WeeklyProjection
    private var today: Date { workspace.today }
    private var calendar: Calendar { workspace.calendar }
    private func total(on dayID: String) -> TimeInterval { projection.sessionDayTotals[dayID, default: 0] }
    @State private var hourHeight: CGFloat = 72
    @State private var selection: Selection?
    private enum Selection: Identifiable {
        case session(RecordedSession), block(CalendarProjectBlock)
        var id: String { switch self { case .session(let value): "session/" + value.id; case .block(let value): "block/" + value.id } }
    }
    private let gutter: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            GeometryReader { viewport in
                let width = max(viewport.size.width, 900)
                let column = (width - gutter) / 7
                KeepScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        dayHeaders(columnWidth: column)
                        ScrollViewReader { reader in
                            KeepScrollView(.vertical) {
                                timeline(width: width, columnWidth: column)
                            }
                            .onAppear { reader.scrollTo("hour-8", anchor: .top) }
                        }
                    }
                    .frame(width: width)
                }
                .background(KeepTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
                .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Weekly recorded entries")

            HStack(spacing: 12) {
                Label("Recorded entries", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("Timer sessions and added entries. Daily total adjustments stay in Timesheet.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                Spacer(minLength: 0)
                zoomButton("minus", label: "Zoom out calendar", disabled: hourHeight <= 48) { hourHeight = max(48, hourHeight - 12) }
                zoomButton("plus", label: "Zoom in calendar", disabled: hourHeight >= 108) { hourHeight = min(108, hourHeight + 12) }
            }
            .accessibilityElement(children: .contain)

            HStack(spacing: 7) {
                Spacer()
                Text("Week view · Monday to Sunday")
            }
            .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
        }
        .sheet(item: $selection) { selected in
            switch selected {
            case .session(let session): CalendarSessionDetail(workspace: workspace, selectedSession: session)
            case .block(let block): CalendarBlockEntries(block: block, workspace: workspace) { selection = .session($0) }
            }
        }
    }

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("TIME").font(.system(size: 9, weight: .medium)).tracking(1)
                .foregroundStyle(KeepTheme.mutedInk).frame(width: gutter)
            ForEach(week.days) { day in
                let isToday = calendar.isDate(day.date, inSameDayAs: today)
                HStack(spacing: 8) {
                    Text(day.number).font(KeepTheme.headingFont(size: 24))
                        .foregroundStyle(isToday ? KeepTheme.surface : KeepTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(isToday ? KeepTheme.accentStrong : .clear, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.label).font(.system(size: 9, weight: .medium)).tracking(1)
                        Text(TimesheetDuration.total(total(on: day.id)))
                            .font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk).monospacedDigit()
                    }
                }
                .frame(width: columnWidth, height: 68)
                .background(day.isWeekend ? KeepTheme.paper : .clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)))
                .accessibilityValue("Recorded time: \(TimesheetDuration.total(total(on: day.id)))\(isToday ? ", today" : "")")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(KeepTheme.border).frame(height: 1) }
    }

    private func timeline(width: CGFloat, columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter)
                ForEach(week.days) { day in
                    Rectangle().fill(day.isWeekend ? KeepTheme.paper : KeepTheme.surface)
                        .frame(width: columnWidth)
                        .overlay(alignment: .leading) { Rectangle().fill(KeepTheme.border.opacity(0.65)).frame(width: 1) }
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 0) {
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(KeepTheme.mutedInk)
                            .frame(width: gutter, alignment: .center).padding(.top, 4)
                        VStack(spacing: 0) {
                            Rectangle().fill(KeepTheme.border.opacity(0.8)).frame(height: 1)
                            Spacer()
                            Rectangle().fill(KeepTheme.border.opacity(0.35)).frame(height: 1)
                            Spacer()
                        }
                    }
                    .frame(height: hourHeight)
                    .id("hour-\(hour)")
                }
            }
            .accessibilityHidden(true)
            ForEach(week.days.indices, id: \.self) { dayIndex in
                let placements = CalendarProjectBlock.placements(projection.calendarBlocksByDay[week.days[dayIndex].id, default: []], hourHeight: Double(hourHeight))
                ForEach(placements) { placement in
                    let laneWidth = (columnWidth - 10) / CGFloat(placement.laneCount)
                    let block = placement.block
                    Button {
                        if block.sessions.count == 1, let session = block.sessions.first { selection = .session(session) }
                        else { selection = .block(block) }
                    } label: {
                        CalendarProjectBlockView(block: block, hourHeight: hourHeight)
                            .frame(width: max(1, laneWidth - 2), height: max(30, CGFloat(block.endMinute - block.startMinute) / 60 * hourHeight - 4))
                    }
                    .buttonStyle(CalendarBlockStyle())
                    .offset(x: gutter + CGFloat(dayIndex) * columnWidth + 5 + CGFloat(placement.lane) * laneWidth,
                            y: min(hourHeight * 24 - 30, CGFloat(block.startMinute) / 60 * hourHeight + 2))
                    .accessibilityLabel("\(block.project.name): \(block.titles.joined(separator: ", "))")
                    .accessibilityValue("\(week.days[dayIndex].label), \(block.startTime) to \(block.endTime), \(block.sessions.count) entries, \(TimesheetDuration.clock(block.seconds)) recorded, \(block.gaps.count) gaps")
                    .help(block.sessions.count == 1 ? "Edit or delete this recorded session" : "Choose a recorded entry to edit or delete. Shaded gaps contain no recorded time.")
                }
            }
            if !projection.hasSessions {
                VStack(spacing: 8) {
                    Text("Your focus finds its place here.").font(KeepTheme.headingFont(size: 22))
                    Text("Start a timer or add an entry to fill your calendar.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                }
                .frame(width: width - gutter, height: hourHeight * 2)
                .offset(x: gutter, y: hourHeight * 8)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: hourHeight * 24)
    }

    private func zoomButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .medium)) }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(disabled)
            .accessibilityLabel(label).help(label)
    }
}

private struct CalendarBlockStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? KeepTheme.focusRing : hovered ? KeepTheme.controlBorder : .clear, lineWidth: 2) }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onHover { hovered = $0 }
    }
}

struct CalendarSessionDetail: View {
    let workspace: WorkspaceModel
    let selectedSession: RecordedSession
    private var session: RecordedSession {
        _ = workspace.readIndex.revision
        return workspace.readIndex.sessions[selectedSession.id] ?? selectedSession
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.timeZoneID) ?? workspace.calendar.timeZone
        return calendar
    }
    @State private var taskName: String
    @State private var startTime: String
    @State private var endTime: String
    @State private var error: String?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(workspace: WorkspaceModel, selectedSession: RecordedSession) {
        self.workspace = workspace
        self.selectedSession = selectedSession
        _taskName = State(initialValue: selectedSession.task)
        _startTime = State(initialValue: selectedSession.startTime)
        _endTime = State(initialValue: selectedSession.editableEndTime)
    }

    private var editedStart: Date? { session.date(for: startTime, isEnd: false) }
    private var editedEnd: Date? { session.date(for: endTime, isEnd: true) }
    private var hasChanges: Bool { taskName != selectedSession.task || startTime != selectedSession.startTime || endTime != selectedSession.editableEndTime }
    private var validTaskName: Bool { taskName.trimmingCharacters(in: .whitespacesAndNewlines).count <= 200 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(session.source.title.uppercased(), systemImage: "clock")
                .font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(KeepTheme.accentStrong)
            Text(session.title).font(KeepTheme.headingFont(size: 27)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).help(session.title)
            Label(session.project.name, systemImage: "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(session.project.labelColor(in: environment))
            Text(session.start, format: Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            VStack(alignment: .leading, spacing: 7) {
                Text("Task name").font(.system(size: 12, weight: .medium))
                TextField("Unnamed task", text: $taskName).modifier(KeepInputStyle())
                    .accessibilityLabel("Session task name").onSubmit(save)
                Text(validTaskName ? "Changes this entry only. Leave blank for an unnamed task." : "Use 200 characters or fewer for the task name.")
                    .font(.system(size: 12)).foregroundStyle(validTaskName ? KeepTheme.mutedInk : KeepTheme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                timeField("Start", value: $startTime)
                timeField("End", value: $endTime)
            }
            HStack {
                Text("Duration")
                Spacer()
                Text(TimesheetDuration.clock(editedEnd?.timeIntervalSince(editedStart ?? session.start) ?? session.seconds))
                    .monospacedDigit()
            }.font(.system(size: 13))
            Text("HH:mm:ss · \(session.timeZoneID) · 24:00 ends at midnight")
                .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete…").foregroundStyle(KeepTheme.accentStrong)
                }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(!workspace.canTrack)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).keyboardShortcut(.cancelAction)
                Button(hasChanges ? "Save" : "Done") { save() }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction)
                    .disabled(!workspace.canTrack || !validTaskName)
            }
        }
        .padding(28).frame(width: 420)
        .background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
        .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
        .sheet(isPresented: $confirmingDelete, onDismiss: {
            if workspace.readIndex.sessions[selectedSession.id] == nil { dismiss() }
        }) {
            SessionDeletionDialog(session: session, canDelete: workspace.canTrack && workspace.readIndex.sessions[session.id] != nil) {
                try workspace.deleteSession(id: session.id)
            }
        }
    }

    @Environment(\.self) private var environment
    private func timeField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextField("HH:mm:ss", text: value).modifier(KeepInputStyle()).monospacedDigit()
                .accessibilityLabel("Session \(title.lowercased()) time").onSubmit(save)
        }
    }

    private func save() {
        guard workspace.canTrack, validTaskName else { return }
        guard hasChanges else { dismiss(); return }
        guard let editedStart, let editedEnd else {
            error = "Enter valid times as HH:mm or HH:mm:ss for this day."
            return
        }
        do {
            try workspace.editSession(id: session.id,
                start: startTime != selectedSession.startTime ? editedStart : nil,
                end: endTime != selectedSession.editableEndTime ? editedEnd : nil,
                task: taskName != selectedSession.task ? taskName : nil)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

#Preview {
    let workspace = TimesheetPreviewData.workspace()
    let week = TimesheetWeek(containing: .now)
    DashboardCalendarView(week: week, workspace: workspace, projection: WeeklyProjection(days: week.dayIDs, index: workspace.readIndex))
        .padding(24).frame(width: 1100, height: 780).background(KeepTheme.paper)
}
