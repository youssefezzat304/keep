import SwiftUI

struct HabitWeekProgress: View {
    let store: HabitStore
    let days: [Date]
    let today: Date
    let selectedID: UUID?
    let onSelect: (Habit) -> Void
    let onLogAmount: (HabitLogSelection) -> Void
    let previousWeek: () -> Void
    let nextWeek: () -> Void
    let goToToday: () -> Void
    @Environment(\.self) private var environment
    private var isCurrentWeek: Bool { days.contains { store.calendar.isDate($0, inSameDayAs: today) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(minLength: 8); weekControls }
                VStack(alignment: .leading, spacing: 12) { title; weekControls }
            }
            if store.habits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No habits yet.").font(.system(size: 22, design: .serif))
                    Text("Add your first habit to start tracking daily progress.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                }.frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading).padding(.top, 12)
            } else {
                KeepScrollView(.horizontal) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text("HABIT").font(.system(size: 10, weight: .medium)).tracking(1)
                                .foregroundStyle(KeepTheme.mutedInk).frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                            ForEach(days, id: \.self) { date in dayHeader(date) }
                        }.padding(.horizontal, 8).padding(.bottom, 8)
                        ForEach(store.habits) { habit in
                            HStack(spacing: 8) {
                                Button { onSelect(habit) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: habit.icon.rawValue).font(.system(size: 16)).foregroundStyle(habit.icon.ink(in: environment))
                                            .frame(width: 32, height: 32)
                                            .background(habit.icon.accent.color.opacity(0.22), in: Circle())
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(habit.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                            Text(habit.goal.summary).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                                        }
                                    }.frame(minWidth: 160, maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                }
                                .buttonStyle(HabitLabelButtonStyle()).help("View \(habit.name) statistics")
                                .accessibilityLabel("View statistics for \(habit.name)")
                                .accessibilityAddTraits(selectedID == habit.id ? .isSelected : [])
                                ForEach(days, id: \.self) { date in
                                    HabitDayControl(store: store, habit: habit, date: date, today: today, onLogAmount: onLogAmount)
                                }
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .background(habit.icon.accent.color.opacity(selectedID == habit.id ? 0.22 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selectedID == habit.id ? habit.icon.ink(in: environment).opacity(0.6) : KeepTheme.border.opacity(0.35), lineWidth: 1).allowsHitTesting(false) }
                        }
                    }.padding(2).frame(width: 480)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isCurrentWeek ? "Current week progress" : "Week progress").font(.system(size: 23, design: .serif))
            if let first = days.first, let last = days.last {
                Text(HabitDates.label(first, calendar: store.calendar, style: .dateTime.day().month(.abbreviated)) + " – " + HabitDates.label(last, calendar: store.calendar, style: .dateTime.day().month(.abbreviated)))
                    .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
            }
        }
    }
    private var weekControls: some View {
        HStack(spacing: 4) {
            Button(action: previousWeek) { Image(systemName: "chevron.left") }.accessibilityLabel("Previous habit week")
            if !isCurrentWeek { Button("Today", action: goToToday) }
            Button(action: nextWeek) { Image(systemName: "chevron.right") }.accessibilityLabel("Next habit week")
        }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
    }
    private func dayHeader(_ date: Date) -> some View {
        let day = TaskDay.id(for: date, calendar: store.calendar)
        let future = day > TaskDay.id(for: today, calendar: store.calendar)
        let total = store.scheduled(on: day)
        let completed = future ? 0 : store.completed(on: day)
        return VStack(spacing: 4) {
            Text(HabitDates.label(date, calendar: store.calendar, style: .dateTime.weekday(.abbreviated))).font(.system(size: 9))
            Text(String(store.calendar.component(.day, from: date))).font(.system(size: 12, weight: .medium))
            ZStack {
                Circle().stroke(KeepTheme.mutedWarm, lineWidth: 3)
                Circle().trim(from: 0, to: total > 0 ? CGFloat(completed) / CGFloat(total) : 0)
                    .stroke(HabitVisualStyle.ink(.teal, in: environment), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(total == 0 ? "—" : "\(completed)").font(.system(size: 9, weight: .medium))
            }.frame(width: 23, height: 23)
        }
        .frame(width: 32).foregroundStyle(store.calendar.isDate(date, inSameDayAs: today) ? HabitVisualStyle.ink(.teal, in: environment) : KeepTheme.mutedInk)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(HabitDates.label(date, calendar: store.calendar, style: .dateTime.weekday(.wide).day().month(.wide).year())), \(completed) of \(total) habits complete")
    }
}

struct HabitDayControl: View {
    let store: HabitStore
    let habit: Habit
    let date: Date
    let today: Date
    let onLogAmount: (HabitLogSelection) -> Void
    var showsDate = false
    @Environment(\.self) private var environment
    private var color: Color { habit.icon.ink(in: environment) }
    private var dayID: String { TaskDay.id(for: date, calendar: store.calendar) }
    private var amount: Int { store.amount(for: habit, on: dayID) }
    private var complete: Bool { store.isComplete(habit, on: dayID) }
    private var enabled: Bool { store.canEdit && habit.isScheduled(on: dayID) && dayID <= TaskDay.id(for: today, calendar: store.calendar) }

    var body: some View {
        Button {
            if habit.goal == .checkIn { store.setAmount(complete ? 0 : 1, habitID: habit.id, on: dayID, today: today) }
            else { onLogAmount(HabitLogSelection(habit: habit, dayID: dayID)) }
        } label: {
            ZStack {
                Circle().fill(complete ? color : KeepTheme.surface)
                    .overlay { Circle().strokeBorder(complete ? color : habit.isScheduled(on: dayID) ? color.opacity(0.65) : KeepTheme.controlBorder.opacity(0.6), lineWidth: 1.3) }
                if complete && !showsDate {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                } else if showsDate {
                    Text(String(store.calendar.component(.day, from: date))).font(.system(size: 10, weight: .medium))
                } else if !habit.isScheduled(on: dayID) { Text("–").font(.system(size: 12)) }
                else if amount > 0 { Text("\(amount)").font(.system(size: 10, weight: .medium)).minimumScaleFactor(0.6).lineLimit(1) }
                if !complete && amount > 0 {
                    Circle().trim(from: 0, to: min(1, CGFloat(amount) / CGFloat(habit.goal.target)))
                        .stroke(color, lineWidth: 2).rotationEffect(.degrees(-90))
                }
                if showsDate && complete {
                    Image(systemName: "checkmark").font(.system(size: 6, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 3)
                }
                if showsDate && store.calendar.isDate(date, inSameDayAs: today) {
                    Circle().strokeBorder(KeepTheme.controlBorder, lineWidth: 2)
                }
            }
            .foregroundStyle(complete ? KeepTheme.surface : KeepTheme.ink).frame(width: 30, height: 30)
        }
        .buttonStyle(HabitCircleButtonStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.6)
        .accessibilityLabel("\(habit.name), \(HabitDates.label(date, calendar: store.calendar, style: .dateTime.weekday(.wide).day().month(.wide).year()))")
        .accessibilityValue(!habit.isScheduled(on: dayID) ? "Not scheduled" : complete ? "Complete, \(amount) of \(habit.goal.target)" : "\(amount) of \(habit.goal.target)")
        .help("\(HabitDates.label(date, calendar: store.calendar, style: .dateTime.weekday(.wide).day().month(.wide).year())) · \(habit.goal.summary) · \(complete ? "Complete" : "\(amount) logged")")
    }
}

struct HabitCircleButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(1).contentShape(Circle())
            .overlay { Circle().strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Keep each habit selectable by keyboard without changing the row geometry.
private struct HabitLabelButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
