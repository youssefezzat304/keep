import SwiftUI

/// Shows January through December, in Monday-first week columns.
struct HabitActivityGrid: View {
    let store: HabitStore
    let today: Date
    let onSelectDay: (Date) -> Void
    let availableWidth: CGFloat
    @Environment(\.self) private var environment

    init(store: HabitStore, today: Date, availableWidth: CGFloat = 740, onSelectDay: @escaping (Date) -> Void) {
        self.store = store
        self.today = today
        self.onSelectDay = onSelectDay
        self.availableWidth = availableWidth
    }
    private var calendar: Calendar { store.calendar }
    private var year: Int { calendar.component(.year, from: today) }
    private var color: Color { HabitVisualStyle.ink(.fern, in: environment) }

    var body: some View {
        let snapshot = store.activity(today: today)
        let columns = snapshot.weeks
        let size = ActivityGridStyle.tileSize(availableWidth: availableWidth, columns: columns.count)
        let ink = color
        VStack(alignment: .leading, spacing: ActivityGridStyle.spacing) {
            HStack {
                Text("Habit activity").font(KeepTheme.headingFont(size: 24))
                Text(String(year)).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                Spacer(minLength: 12)
            }
            HStack(alignment: .top, spacing: ActivityGridStyle.tileSpacing) {
                ForEach(columns.indices, id: \.self) { index in
                    VStack(spacing: ActivityGridStyle.monthSpacing) {
                        VStack(spacing: ActivityGridStyle.tileSpacing) {
                            ForEach(0..<7) { row in dailyTile(columns[index].days[row], size: size, ink: ink) }
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
                HStack(spacing: 4) {
                    Text("Less").font(.system(size: 10))
                    ForEach(0..<5) { level in RoundedRectangle(cornerRadius: 2).fill(fill(level, ink: ink)).frame(width: 9, height: 9) }
                    Text("More").font(.system(size: 10))
                }.foregroundStyle(KeepTheme.mutedInk)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Intensity: zero, one, two, three, or four or more habits completed per day")
            }
        }
    }
    private func fill(_ count: Int, ink: Color) -> Color {
        ActivityGridStyle.fill(level: count, ink: ink)
    }
    private func dailyTile(_ day: HabitActivitySnapshot.Day, size: CGFloat, ink: Color) -> some View {
        Button { onSelectDay(day.date) } label: {
            RoundedRectangle(cornerRadius: 2).fill(fill(day.count, ink: ink)).frame(width: size, height: size)
        }
        .buttonStyle(ActivitySquareButtonStyle()).disabled(!day.inYear || day.future)
        .opacity(day.inYear ? 1 : 0)
        .help(day.label).accessibilityLabel(day.label).accessibilityHidden(!day.inYear)
    }
}
