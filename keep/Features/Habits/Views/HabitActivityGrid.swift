import SwiftUI

enum HabitActivityMode: String, CaseIterable, Identifiable {
    case monthly, weekly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Both modes show January through December, in Monday-first week columns.
struct HabitActivityGrid: View {
    let store: HabitStore
    let today: Date
    let onSelectDay: (Date) -> Void
    @State private var mode: HabitActivityMode
    let availableWidth: CGFloat
    @Environment(\.self) private var environment

    init(store: HabitStore, today: Date, mode: HabitActivityMode = .monthly, availableWidth: CGFloat = 740, onSelectDay: @escaping (Date) -> Void) {
        self.store = store
        self.today = today
        self.onSelectDay = onSelectDay
        self.availableWidth = availableWidth
        _mode = State(initialValue: mode)
    }
    private var calendar: Calendar { store.calendar }
    private var weeks: [[Date]] { HabitDates.yearWeeks(containing: today, calendar: calendar) }
    private var year: Int { calendar.component(.year, from: today) }
    private var color: Color { HabitVisualStyle.ink(mode == .monthly ? .fern : .periwinkle, in: environment) }
    private var tileSize: CGFloat { max(6, min(11, (availableWidth - CGFloat(weeks.count - 1) * 3) / CGFloat(max(1, weeks.count)))) }

    var body: some View {
        let columns = weeks
        let totals = columns.map { week in week.reduce(0) { $0 + completionCount($1) } }
        let peak = totals.max() ?? 0
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Habit activity").font(.system(size: 24, design: .serif))
                Text(String(year)).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                Spacer(minLength: 12)
                controls
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(columns.indices, id: \.self) { index in
                    VStack(spacing: 7) {
                        if mode == .monthly {
                            VStack(spacing: 3) {
                                ForEach(0..<7) { row in dailyTile(columns[index][row]) }
                            }
                        } else {
                            weeklyColumn(week: columns[index], total: totals[index], peak: peak)
                        }
                        Text(monthLabel(for: columns[index]))
                            .font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
                            .fixedSize().frame(width: tileSize, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Text("\(totals.reduce(0, +)) daily goals met in \(String(year))")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
                Spacer()
                if mode == .monthly {
                    HStack(spacing: 4) {
                        Text("Less").font(.system(size: 10))
                        ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 2).fill(fill(level)).frame(width: 9, height: 9) }
                        Text("More").font(.system(size: 10))
                    }.foregroundStyle(KeepTheme.mutedInk)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Intensity: zero, one, two, three, or four or more habits completed per day")
                } else {
                    Text("Weekly totals").font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
                }
            }
        }
    }
    private func completionCount(_ date: Date) -> Int {
        guard calendar.component(.year, from: date) == year,
              TaskDay.id(for: date, calendar: calendar) <= TaskDay.id(for: today, calendar: calendar) else { return 0 }
        return store.completed(on: TaskDay.id(for: date, calendar: calendar))
    }
    private func monthLabel(for week: [Date]) -> String {
        guard let first = week.first(where: { calendar.component(.year, from: $0) == year && calendar.component(.day, from: $0) == 1 }) else { return " " }
        return HabitDates.label(first, calendar: calendar, style: .dateTime.month(.abbreviated))
    }
    private func fill(_ count: Int) -> Color {
        count == 0 ? KeepTheme.mutedWarm.opacity(0.55) : color.opacity([0.0, 0.3, 0.5, 0.75, 1.0][min(4, count)])
    }
    private func dailyTile(_ date: Date) -> some View {
        let withinYear = calendar.component(.year, from: date) == year
        let future = TaskDay.id(for: date, calendar: calendar) > TaskDay.id(for: today, calendar: calendar)
        let count = completionCount(date)
        let description = "\(HabitDates.label(date, calendar: calendar, style: .dateTime.day().month(.wide).year())): \(count) habits completed"
        return Button { onSelectDay(date) } label: {
            RoundedRectangle(cornerRadius: 2).fill(fill(count)).frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(HabitSquareButtonStyle()).disabled(!withinYear || future)
        .opacity(!withinYear ? 0 : future ? 0.3 : 1)
        .help(description).accessibilityLabel(description).accessibilityHidden(!withinYear)
    }
    private func weeklyColumn(week: [Date], total: Int, peak: Int) -> some View {
        let height = HabitDates.weeklyHeight(completions: total, peak: peak)
        let description = "Week of \(week.first.map { HabitDates.label($0, calendar: calendar, style: .dateTime.day().month(.wide)) } ?? ""): \(total) habits completed"
        return Button {
            if let date = week.first(where: { calendar.component(.year, from: $0) == year }) { onSelectDay(date) }
        } label: {
            VStack(spacing: 3) {
                ForEach(0..<7) { row in
                    RoundedRectangle(cornerRadius: 2).fill(row >= 7 - height ? color : KeepTheme.mutedWarm.opacity(0.25))
                        .frame(width: tileSize, height: tileSize)
                }
            }
        }
        .buttonStyle(HabitSquareButtonStyle())
        .disabled(week.allSatisfy { $0 > today }).help(description).accessibilityLabel(description)
    }
    private var controls: some View {
        HStack(spacing: 4) {
            ForEach(HabitActivityMode.allCases) { option in
                Button(option.title) { mode = option }
                    .buttonStyle(KeepButtonStyle(emphasis: option == mode ? .primary : .quiet))
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }.accessibilityLabel("Activity grouping")
    }
}

private struct HabitSquareButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay {
            RoundedRectangle(cornerRadius: 2).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
