import SwiftUI

struct HabitStatisticsView: View {
    let store: HabitStore
    let habit: Habit?
    let today: Date
    let onLogAmount: (HabitLogSelection) -> Void
    @Environment(\.self) private var environment
    @State private var monthOffset = 0
    private var month: Date { store.calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let habit {
                HStack(spacing: 10) {
                    Image(systemName: habit.icon.rawValue).font(.system(size: 21)).foregroundStyle(habit.icon.ink(in: environment))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name).font(KeepTheme.headingFont(size: 22)).fixedSize(horizontal: false, vertical: true)
                        Text(habit.goal.summary + " · " + habit.frequencySummary(calendar: store.calendar))
                            .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                    }
                }
                let stats = store.statistics(for: habit, month: month, today: today)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metric("Month total", value: "\(stats.monthlyCompletions)", suffix: "completed days", symbol: "checkmark.circle", accent: .teal, background: KeepTheme.sage)
                    metric("All time", value: "\(stats.totalCompletions)", suffix: "completed days", symbol: "chart.bar", accent: .denim, background: KeepTheme.mistBlue)
                    metric("Success rate", value: "\(Int((stats.monthlyRate * 100).rounded()))%", suffix: "\(stats.monthlyScheduled) days due", symbol: "circle.lefthalf.filled", accent: .ochre, background: KeepTheme.highlight)
                    metric("Current streak", value: "\(stats.currentStreak)", suffix: "Best: \(stats.bestStreak) check-ins", symbol: "flame", accent: .rose, background: FocusProject.Accent.rose.color)
                        .help("Consecutive scheduled check-ins. Rest days do not break a streak.")
                }
                HabitVisualStyle.divider().frame(height: 1)
                HStack(spacing: 5) {
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous statistics month")
                    Spacer(minLength: 0)
                    Text(HabitDates.label(month, calendar: store.calendar, style: .dateTime.month(.wide).year())).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next statistics month")
                }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                    ForEach(Array(HabitDates.weekdayLabels(calendar: store.calendar).enumerated()), id: \.offset) { _, day in
                        Text(day).font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
                    }
                    ForEach(HabitDates.monthGrid(containing: month, calendar: store.calendar), id: \.self) { date in
                        if store.calendar.isDate(date, equalTo: month, toGranularity: .month) {
                            HabitDayControl(store: store, habit: habit, date: date, today: today, onLogAmount: onLogAmount, showsDate: true)
                        } else { Color.clear.frame(height: 32).accessibilityHidden(true) }
                    }
                }
            } else {
                Text("Habit overview").font(KeepTheme.headingFont(size: 22))
                Text("Completion totals, streaks, and a calendar will appear here.")
                    .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func metric(_ title: String, value: String, suffix: String, symbol: String, accent: FocusProject.Accent, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(KeepTheme.mutedInk)
            Text(value).font(KeepTheme.headingFont(size: 30)).foregroundStyle(KeepTheme.readableAccent(accent.color, on: [KeepTheme.surface, background], environment: environment))
            Text(suffix).font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12).background(background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
