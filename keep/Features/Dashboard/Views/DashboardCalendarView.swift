import SwiftUI

struct DashboardCalendarView: View {
    let week: TimesheetWeek
    let today: Date
    let calendar: Calendar
    @State private var hourHeight: CGFloat = 72
    @State private var selectedSession: DashboardCalendarSample?
    private let gutter: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("Sample sessions", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("A preview of your calendar. Your recorded time lives in Timesheet.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                Spacer(minLength: 0)
                zoomButton("minus", label: "Zoom out calendar", disabled: hourHeight <= 48) { hourHeight = max(48, hourHeight - 12) }
                zoomButton("plus", label: "Zoom in calendar", disabled: hourHeight >= 108) { hourHeight = min(108, hourHeight + 12) }
            }
            .accessibilityElement(children: .contain)

            GeometryReader { viewport in
                let width = max(viewport.size.width, 900)
                let column = (width - gutter) / 7
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        dayHeaders(columnWidth: column)
                        ScrollViewReader { reader in
                            ScrollView(.vertical) {
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
            .accessibilityLabel("Weekly calendar preview")

            HStack(spacing: 7) {
                Image(systemName: "sun.max").foregroundStyle(KeepTheme.accentStrong)
                Text("A little structure. Plenty of breathing room.")
                Spacer()
                Text("Week view · Monday to Sunday")
            }
            .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
        }
        .sheet(item: $selectedSession) { session in
            CalendarSampleDetail(session: session, week: week, calendar: calendar)
        }
    }

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("TIME").font(.system(size: 9, weight: .medium)).tracking(1)
                .foregroundStyle(KeepTheme.mutedInk).frame(width: gutter)
            ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                let isToday = calendar.isDate(day.date, inSameDayAs: today)
                HStack(spacing: 8) {
                    Text(day.number).font(.system(size: 24, design: .serif))
                        .foregroundStyle(isToday ? KeepTheme.surface : KeepTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(isToday ? KeepTheme.accentStrong : .clear, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.label).font(.system(size: 9, weight: .medium)).tracking(1)
                        Text(TimesheetDuration.total(DashboardCalendarSamples.total(on: index)))
                            .font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk).monospacedDigit()
                    }
                }
                .frame(width: columnWidth, height: 68)
                .background(day.isWeekend ? KeepTheme.paper : .clear)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)))
                .accessibilityValue("Sample time: \(TimesheetDuration.total(DashboardCalendarSamples.total(on: index)))\(isToday ? ", today" : "")")
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
            ForEach(DashboardCalendarSamples.sessions) { session in
                Button { selectedSession = session } label: {
                    CalendarSampleBlock(session: session)
                        .frame(width: columnWidth - 10, height: max(30, CGFloat(session.endMinute - session.startMinute) / 60 * hourHeight - 4))
                }
                .buttonStyle(CalendarBlockStyle())
                .offset(x: gutter + CGFloat(session.day) * columnWidth + 5, y: CGFloat(session.startMinute) / 60 * hourHeight + 2)
                .accessibilityLabel("Sample session: \(session.task), \(session.project.name)")
                .accessibilityValue("\(week.days[session.day].label), \(calendarTime(session.startMinute)) to \(calendarTime(session.endMinute)), \(TimesheetDuration.total(session.seconds))")
                .help("View sample session details")
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

private struct CalendarSampleBlock: View {
    let session: DashboardCalendarSample
    var body: some View {
        GeometryReader { bounds in
            HStack(spacing: 0) {
                Rectangle().fill(session.project.accentColor).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.task).font(.system(size: 11, weight: .medium))
                        .lineLimit(bounds.size.height >= 90 ? 2 : 1)
                    if bounds.size.height >= 58 {
                        Text(session.project.name).font(.system(size: 10)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Text(calendarTime(session.startMinute)).font(.system(size: 9))
                        Spacer(minLength: 2)
                        Text(TimesheetDuration.total(session.seconds)).font(.system(size: 10, weight: .medium))
                    }
                    .monospacedDigit()
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
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

private struct CalendarSampleDetail: View {
    let session: DashboardCalendarSample
    let week: TimesheetWeek
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("SAMPLE SESSION", systemImage: "sparkles")
                .font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(KeepTheme.accentStrong)
            Text(session.task).font(.system(size: 27, design: .serif))
            Label(session.project.name, systemImage: "folder")
                .font(.system(size: 14, weight: .medium))
            Text(week.days[session.day].date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            HStack {
                Text("\(calendarTime(session.startMinute)) – \(calendarTime(session.endMinute))")
                Spacer()
                Text(TimesheetDuration.total(session.seconds))
            }.font(.system(size: 14)).monospacedDigit()
            Text("This is a sample for the calendar preview.").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
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

private func calendarTime(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

#Preview {
    DashboardCalendarView(week: TimesheetWeek(containing: .now), today: .now, calendar: .current)
        .padding(24).frame(width: 1100, height: 780).background(KeepTheme.paper)
}
