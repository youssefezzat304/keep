import SwiftUI

struct HabitTrackerView: View {
    let store: HabitStore
    var today: Date = .now
    @State private var showsCreation = false
    @State private var activityMode = HabitActivityMode.monthly
    @State private var selectedHabitID: UUID?
    @State private var weekSelection = TaskDaySelection()
    @State private var logSelection: HabitLogSelection?
    private var selectedHabit: Habit? { store.habits.first { $0.id == selectedHabitID } ?? store.habits.first }
    private var days: [Date] { HabitDates.weekDays(containing: weekSelection.date(today: today, calendar: store.calendar), calendar: store.calendar) }

    var body: some View {
        GeometryReader { geometry in
            KeepScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Habit tracker").font(KeepTheme.headingFont(size: 36))
                        Spacer(minLength: 12)
                        Button { showsCreation = true } label: { Label("Add habit", systemImage: "plus") }
                            .buttonStyle(KeepButtonStyle(emphasis: .primary)).disabled(!store.canEdit)
                    }
                    if let error = store.persistenceError {
                        HStack {
                            Text(error).font(.system(size: 13))
                            Spacer()
                            Button("Retry") { store.retryPersistence() }.buttonStyle(KeepButtonStyle())
                        }.padding(12).background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 26) {
                        HabitActivityGrid(store: store, today: today, mode: $activityMode, availableWidth: geometry.size.width - 44) { date in
                            weekSelection.select(date, today: today, calendar: store.calendar)
                        }
                        HabitVisualStyle.divider().frame(height: 1)
                        if geometry.size.width >= 900 {
                            HStack(alignment: .top, spacing: 36) {
                                weekProgress.frame(width: 480)
                                statistics.frame(maxWidth: 560, alignment: .topLeading)
                            }
                            .overlay(alignment: .leading) {
                                HabitVisualStyle.divider(vertical: true).frame(width: 1)
                                    .padding(.vertical, 8).offset(x: 498)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            weekProgress.frame(width: 480).frame(maxWidth: .infinity, alignment: .center)
                            HabitVisualStyle.divider().frame(height: 1)
                            statistics
                        }
                    }
                    .cardStyle()
                    .overlay {
                        RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border.opacity(0.6), lineWidth: 1)
                            .allowsHitTesting(false)
                    }

                }.padding(.bottom, 4).frame(width: geometry.size.width, alignment: .topLeading)
            }
        }
        .foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
        .sheet(isPresented: $showsCreation) { HabitCreationDialog(store: store, today: today) }
        .sheet(item: $logSelection) { selection in HabitAmountDialog(selection: selection, store: store, today: today) }
    }
    private var weekProgress: some View {
        HabitWeekProgress(store: store, days: days, today: today, selectedID: selectedHabit?.id, onSelect: { selectedHabitID = $0.id },
            onLogAmount: { logSelection = $0 }, previousWeek: { weekSelection.move(by: -7, today: today, calendar: store.calendar) },
            nextWeek: { weekSelection.move(by: 7, today: today, calendar: store.calendar) }, goToToday: { weekSelection.goToToday() })
    }
    private var statistics: some View { HabitStatisticsView(store: store, habit: selectedHabit, today: today, onLogAmount: { logSelection = $0 }) }
}

#Preview("Habit tracker") {
    AppShellView(initialTab: .habits).frame(width: 1000, height: 900)
}
