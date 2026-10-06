import SwiftUI

struct DashboardCalendarView: View {
    let week: TimesheetWeek
    let workspace: WorkspaceModel
    private var today: Date { workspace.today }
    private var calendar: Calendar { workspace.calendar }
    private var sessions: [RecordedSession] { workspace.ledger.sessions.filter { week.dayIDs.contains($0.dayID) } }
    private func total(on dayID: String) -> TimeInterval { sessions.filter { $0.dayID == dayID }.reduce(0) { $0 + $1.seconds } }
    @State private var hourHeight: CGFloat = 72
    @State private var selectedSession: RecordedSession?
    private let gutter: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("Timer sessions", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("Focus and Flow, as they happened. Manual totals stay in Timesheet.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                Spacer(minLength: 0)
                zoomButton("minus", label: "Zoom out calendar", disabled: hourHeight <= 48) { hourHeight = max(48, hourHeight - 12) }
                zoomButton("plus", label: "Zoom in calendar", disabled: hourHeight >= 108) { hourHeight = min(108, hourHeight + 12) }
            }
            .accessibilityElement(children: .contain)

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
            .accessibilityLabel("Weekly recorded sessions")

            HStack(spacing: 7) {
                Image(systemName: "sun.max").foregroundStyle(KeepTheme.accentStrong)
                Text("A little structure. Plenty of breathing room.")
                Spacer()
                Text("Week view · Monday to Sunday")
            }
            .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
        }
        .sheet(item: $selectedSession) { session in
            CalendarSessionDetail(workspace: workspace, selectedSession: session)
        }
    }

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("TIME").font(.system(size: 9, weight: .medium)).tracking(1)
                .foregroundStyle(KeepTheme.mutedInk).frame(width: gutter)
            ForEach(week.days) { day in
                let isToday = calendar.isDate(day.date, inSameDayAs: today)
                HStack(spacing: 8) {
                    Text(day.number).font(.system(size: 24, design: .serif))
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
                let placements = placements(on: week.days[dayIndex].id)
                let lanes = max(1, (placements.map(\.lane).max() ?? 0) + 1)
                let laneWidth = (columnWidth - 10) / CGFloat(lanes)
                ForEach(placements) { placement in
                    let session = placement.session
                    Button { selectedSession = session } label: {
                        CalendarSessionBlock(session: session)
                            .frame(width: max(1, laneWidth - 2), height: max(30, CGFloat(session.endMinute - session.startMinute) / 60 * hourHeight - 4))
                    }
                    .buttonStyle(CalendarBlockStyle())
                    .offset(x: gutter + CGFloat(dayIndex) * columnWidth + 5 + CGFloat(placement.lane) * laneWidth,
                            y: min(hourHeight * 24 - 30, CGFloat(session.startMinute) / 60 * hourHeight + 2))
                    .accessibilityLabel("\(session.source.title): \(session.title), \(session.project.name)")
                    .accessibilityValue("\(week.days[dayIndex].label), \(session.startTime) to \(session.endTime), \(TimesheetDuration.clock(session.seconds))")
                    .help("View recorded session details")
                }
            }
            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("Your focus finds its place here.").font(.system(size: 22, design: .serif))
                    Text("Start a timer to record your first session.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                }
                .frame(width: width - gutter, height: hourHeight * 2)
                .offset(x: gutter, y: hourHeight * 8)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: hourHeight * 24)
    }

    private struct Placement: Identifiable {
        let session: RecordedSession
        let lane: Int
        var id: String { session.id }
    }
    private func placements(on dayID: String) -> [Placement] {
        var ends: [Double] = []
        return sessions.filter { $0.dayID == dayID }.sorted { $0.start < $1.start }.map { session in
            let lane = ends.firstIndex { $0 <= session.startMinute } ?? ends.count
            let end = max(session.endMinute, session.startMinute + 34 / Double(hourHeight) * 60)
            if lane == ends.count { ends.append(end) } else { ends[lane] = end }
            return Placement(session: session, lane: lane)
        }
    }

    private func zoomButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .medium)) }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(disabled)
            .accessibilityLabel(label).help(label)
    }
}

private struct CalendarSessionBlock: View {
    let session: RecordedSession
    var body: some View {
        GeometryReader { bounds in
            HStack(spacing: 0) {
                Rectangle().fill(session.project.accentColor).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.system(size: 11, weight: .medium))
                        .lineLimit(bounds.size.height >= 90 ? 2 : 1)
                    if bounds.size.height >= 74 {
                        Text(session.project.name).font(.system(size: 10)).lineLimit(1)
                    }
                    if bounds.size.height >= 48 {
                        Spacer(minLength: 0)
                        HStack {
                            Text(calendarTime(session.startMinute)).font(.system(size: 9))
                            Spacer(minLength: 2)
                            Text(TimesheetDuration.clock(session.seconds)).font(.system(size: 10, weight: .medium))
                        }
                        .monospacedDigit()
                    }
                }
                .padding(bounds.size.height < 48 ? 6 : 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(KeepTheme.ink)
            .background(session.project.accentColor.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(session.project.accentColor.opacity(0.7), lineWidth: 1) }
        }
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

private struct CalendarSessionDetail: View {
    let workspace: WorkspaceModel
    let selectedSession: RecordedSession
    private var session: RecordedSession {
        workspace.ledger.sessions.first { $0.id == selectedSession.id } ?? selectedSession
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.timeZoneID) ?? workspace.calendar.timeZone
        return calendar
    }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(session.source.title.uppercased(), systemImage: "clock")
                .font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(KeepTheme.accentStrong)
            Text(session.title).font(.system(size: 27, design: .serif))
            Label(session.project.name, systemImage: "folder")
                .font(.system(size: 14, weight: .medium))
            Text(session.start, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            HStack {
                Text("\(session.startTime) – \(session.endTime)")
                Spacer()
                Text(TimesheetDuration.clock(session.seconds))
            }.font(.system(size: 14)).monospacedDigit()
            Text("Recorded with your timer · \(session.timeZoneID)").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 380)
        .background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
        .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
}

private func calendarTime(_ minute: Double) -> String {
    let value = Int(minute)
    return String(format: "%02d:%02d", value / 60, value % 60)
}

#Preview {
    DashboardCalendarView(week: TimesheetWeek(containing: .now), workspace: WorkspaceModel())
        .padding(24).frame(width: 1100, height: 780).background(KeepTheme.paper)
}
