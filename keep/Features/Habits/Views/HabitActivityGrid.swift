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
    @Binding private var mode: HabitActivityMode
    let availableWidth: CGFloat
    @Environment(\.self) private var environment

    init(store: HabitStore, today: Date, mode: Binding<HabitActivityMode> = .constant(.monthly), availableWidth: CGFloat = 740, onSelectDay: @escaping (Date) -> Void) {
        self.store = store
        self.today = today
        self.onSelectDay = onSelectDay
        self.availableWidth = availableWidth
        _mode = mode
    }
    private var calendar: Calendar { store.calendar }
    private var year: Int { calendar.component(.year, from: today) }
    private var color: Color { HabitVisualStyle.ink(mode == .monthly ? .fern : .periwinkle, in: environment) }
    private func tileSize(columns: Int) -> CGFloat { max(6, min(11, (availableWidth - CGFloat(columns - 1) * 3) / CGFloat(max(1, columns)))) }

    var body: some View {
        let snapshot = store.activity(today: today)
        let columns = snapshot.weeks
        let size = tileSize(columns: columns.count)
        let ink = color
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
                                ForEach(0..<7) { row in dailyTile(columns[index].days[row], size: size, ink: ink) }
                            }
                        } else {
                            weeklyColumn(columns[index], size: size, ink: ink)
                        }
                        Text(columns[index].month)
                            .font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
                            .fixedSize().frame(width: size, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Text("\(snapshot.total) daily goals met in \(String(year))")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
                Spacer()
                if mode == .monthly {
                    HStack(spacing: 4) {
                        Text("Less").font(.system(size: 10))
                        ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 2).fill(fill(level, ink: ink)).frame(width: 9, height: 9) }
                        Text("More").font(.system(size: 10))
                    }.foregroundStyle(KeepTheme.mutedInk)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Intensity: zero, one, two, three, or four or more habits completed per day")
                } else {
                    Text("1 square = 1 goal · 7+ per week").font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
                }
            }
        }
    }
    private func fill(_ count: Int, ink: Color) -> Color {
        count == 0 ? KeepTheme.mutedWarm.opacity(0.55) : ink.opacity([0.0, 0.3, 0.5, 0.75, 1.0][min(4, count)])
    }
    private func dailyTile(_ day: HabitActivitySnapshot.Day, size: CGFloat, ink: Color) -> some View {
        Button { onSelectDay(day.date) } label: {
            RoundedRectangle(cornerRadius: 2).fill(fill(day.count, ink: ink)).frame(width: size, height: size)
        }
        .buttonStyle(HabitSquareButtonStyle()).disabled(!day.inYear || day.future)
        .opacity(!day.inYear ? 0 : day.future ? 0.3 : 1)
        .help(day.label).accessibilityLabel(day.label).accessibilityHidden(!day.inYear)
    }
    private func weeklyColumn(_ week: HabitActivitySnapshot.Week, size: CGFloat, ink: Color) -> some View {
        let height = HabitDates.weeklyHeight(completions: week.total)
        return Button {
            if let day = week.days.first(where: { $0.inYear }) { onSelectDay(day.date) }
        } label: {
            VStack(spacing: 3) {
                ForEach(0..<7) { row in
                    RoundedRectangle(cornerRadius: 2).fill(row >= 7 - height ? ink : KeepTheme.mutedWarm.opacity(0.25))
                        .frame(width: size, height: size)
                }
            }
        }
        .buttonStyle(HabitSquareButtonStyle())
        .disabled(week.days.allSatisfy { $0.future }).help(week.label).accessibilityLabel(week.label)
    }
    private var controls: some View {
        HStack(spacing: 4) {
            ForEach(HabitActivityMode.allCases) { option in
                Button(option.title) { mode = option }
                    .buttonStyle(KeepButtonStyle(emphasis: option == mode ? .primary : .quiet))
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(4).background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
        .accessibilityElement(children: .contain).accessibilityLabel("Activity grouping")
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
