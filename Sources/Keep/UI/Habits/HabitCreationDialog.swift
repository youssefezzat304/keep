import SwiftUI

struct HabitCreationDialog: View {
    let store: HabitStore
    private let editingHabit: Habit?
    @Environment(\.dismiss) private var dismiss
    @State private var weekdays = Set(HabitWeekday.allCases)
    @Environment(\.self) private var environment
    @State private var name = ""
    @State private var icon = HabitIcon.checkmark
    @State private var goalKind = GoalKind.checkIn
    @State private var target = "20"
    @State private var unit = HabitUnit.minutes
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasEndDate = false
    @State private var weeklyEnabled = false
    @State private var weeklyGoal = "3"
    @State private var weeklyMinimum = "1"
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    enum GoalKind: String, CaseIterable { case checkIn, amount
        var title: String { self == .checkIn ? "Daily check-in" : "Daily target" }
    }

    init(store: HabitStore, today: Date = .now, goal: HabitGoal = .checkIn, endDate: Date? = nil, weekdays: Set<HabitWeekday> = Set(HabitWeekday.allCases), habit: Habit? = nil) {
        self.store = store
        editingHabit = habit
        _weeklyEnabled = State(initialValue: habit?.weeklyTargets != nil)
        if let saved = habit?.weeklyTargets {
            let hours = habit?.weeklyUnit == "minutes"
            _weeklyGoal = State(initialValue: hours ? WeeklyTargets.hoursText(saved.goal) : String(saved.goal))
            _weeklyMinimum = State(initialValue: hours ? WeeklyTargets.hoursText(saved.minimum) : String(saved.minimum))
        }
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.icon ?? .checkmark)
        _weekdays = State(initialValue: habit.map { Set($0.weekdays) } ?? weekdays)
        let start = habit.flatMap { TaskDay.date(for: $0.startDay, calendar: store.calendar) } ?? today
        let end = habit.map { $0.endDay.flatMap { TaskDay.date(for: $0, calendar: store.calendar) } } ?? endDate
        if case .amount(let value, let unit) = habit?.goal ?? goal {
            _goalKind = State(initialValue: .amount)
            _target = State(initialValue: String(value))
            _unit = State(initialValue: unit)
        }
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: end ?? store.calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        _hasEndDate = State(initialValue: end != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editingHabit == nil ? "Add habit" : "Edit habit").font(KeepTheme.headingFont(size: 28))
            KeepScrollView {
            VStack(alignment: .leading, spacing: 18) {
            TextField("Habit name", text: $name).modifier(KeepInputStyle()).focused($nameFocused)
                .accessibilityLabel("Habit name")
                .onSubmit(save)
                .onChange(of: name) { error = nil }
            VStack(alignment: .leading, spacing: 10) {
                Text("Icon").font(.system(size: 12, weight: .medium)).foregroundStyle(KeepTheme.mutedInk)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(HabitIcon.allCases) { option in
                        Button { icon = option } label: {
                            Image(systemName: option.rawValue).font(.system(size: 17)).frame(width: 28)
                                .foregroundStyle(icon == option ? KeepTheme.surface : option.ink(in: environment))
                        }
                        .buttonStyle(KeepButtonStyle(emphasis: icon == option ? .primary : .quiet))
                        .accessibilityLabel(option.title).accessibilityAddTraits(icon == option ? .isSelected : [])
                        .help(option.title)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                frequency
                if editingHabit != nil {
                    Text("Saved progress is kept when you change days. Completion rates and streaks use the new schedule.")
                        .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                }
                WeeklyTargetsFields(enabled: $weeklyEnabled, goal: $weeklyGoal, minimum: $weeklyMinimum,
                    unit: usesHours ? "hours" : goalKind == .checkIn ? "check-ins" : "times",
                    maximum: usesHours ? "168" : goalKind == .checkIn ? "7" : "70,000")
                VStack(alignment: .leading, spacing: 18) {
                labeled("Daily goal") {
                    KeepSegmentedPicker(label: "Habit goal", selection: $goalKind, options: GoalKind.allCases, title: { $0.title })
                }
                if goalKind == .amount {
                    HStack(spacing: 12) {
                        Text("Per day").font(.system(size: 13, weight: .medium)).frame(width: 90, alignment: .leading)
                        TextField("Amount", text: $target).modifier(KeepInputStyle())
                            .frame(width: 80).accessibilityLabel("Daily target amount")
                        KeepSegmentedPicker(label: "Target unit", selection: $unit, options: HabitUnit.allCases, title: { $0.title })
                    }
                }
                labeled("Starts") { HabitDateField(label: "Start date", date: $startDate, calendar: store.calendar) }
                Toggle("Set an end date", isOn: $hasEndDate).toggleStyle(KeepCheckboxStyle())
                if hasEndDate {
                    labeled("Ends") { HabitDateField(label: "End date", date: $endDate, calendar: store.calendar) }
                }
                }.disabled(editingHabit != nil)
            }
            }
            }.frame(maxHeight: 440)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(KeepButtonStyle(emphasis: .quiet))
                Spacer()
                Button(editingHabit == nil ? "Add habit" : "Save changes", action: save).keyboardShortcut(.defaultAction).buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weekdays.isEmpty || !store.canEdit)
            }
        }
        .padding(24).frame(width: 460)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
        .environment(\.calendar, store.calendar)
        .environment(\.timeZone, store.calendar.timeZone)
        .onAppear { nameFocused = true }
    }

    private var frequency: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Frequency").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(weekdays.count == 7 ? "Every day" : weekdays.isEmpty ? "Choose a day" : "\(weekdays.count) days a week")
                    .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
            }
            HStack(spacing: 12) {
                ForEach(HabitWeekday.allCases) { day in
                    let selected = weekdays.contains(day)
                    Button {
                        if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                        error = nil
                    } label: {
                        Text(day.shortTitle(calendar: store.calendar)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected ? KeepTheme.surface : KeepTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(selected ? icon.ink(in: environment) : KeepTheme.mutedWarm.opacity(0.4), in: Circle())
                            .overlay(alignment: .bottom) {
                                if selected { Image(systemName: "checkmark").font(.system(size: 5, weight: .bold)).foregroundStyle(KeepTheme.surface).padding(.bottom, 3) }
                            }
                    }
                    .buttonStyle(HabitCircleButtonStyle()).accessibilityLabel(day.title(calendar: store.calendar))
                    .accessibilityValue(selected ? "Scheduled" : "Rest day")
                    .accessibilityAddTraits(selected ? .isSelected : []).help(day.title(calendar: store.calendar))
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).font(.system(size: 13, weight: .medium)).frame(width: 90, alignment: .leading); content(); Spacer(minLength: 0) }
    }
    private var usesHours: Bool { goalKind == .amount && unit == .minutes }
    private func targets() throws -> WeeklyTargets? {
        guard weeklyEnabled else { return nil }
        return try WeeklyTargets.parse(goal: weeklyGoal, minimum: weeklyMinimum, hours: usesHours,
            maximum: usesHours ? WeeklyTargets.maximumMinutes : goalKind == .checkIn ? 7 : 70000)
    }
    private func save() {
        if let editingHabit {
            do {
                try store.update(habitID: editingHabit.id, name: name, icon: icon, weekdays: HabitWeekday.allCases.filter { weekdays.contains($0) }, weeklyTargets: targets())
                dismiss()
            } catch { self.error = error.localizedDescription }
            return
        }
        let goal: HabitGoal
        if goalKind == .amount {
            guard let value = Int(target) else { error = HabitError.invalidGoal.localizedDescription; return }
            goal = .amount(target: value, unit: unit)
        } else { goal = .checkIn }
        do {
            try store.add(name: name, icon: icon, startDay: TaskDay.id(for: startDate, calendar: store.calendar), endDay: hasEndDate ? TaskDay.id(for: endDate, calendar: store.calendar) : nil, goal: goal, weekdays: HabitWeekday.allCases.filter { weekdays.contains($0) }, weeklyTargets: targets())
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct HabitLogSelection: Identifiable {
    let habit: Habit
    let dayID: String
    var id: String { "\(habit.id)/\(dayID)" }
}

struct HabitAmountDialog: View {
    let selection: HabitLogSelection
    let store: HabitStore
    let today: Date
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var error: String?
    init(selection: HabitLogSelection, store: HabitStore, today: Date) {
        self.selection = selection; self.store = store; self.today = today
        _amount = State(initialValue: String(store.amount(for: selection.habit, on: selection.dayID)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(selection.habit.name, systemImage: selection.habit.icon.rawValue).font(KeepTheme.headingFont(size: 24))
            Text(selection.dayID + " · " + selection.habit.goal.summary).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            TextField("Amount", text: $amount).modifier(KeepInputStyle()).accessibilityLabel("Completed amount")
                .onSubmit(save)
                .onChange(of: amount) { error = nil }
            Text("Use 0 to clear this day’s progress.").font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
            Button("Meet daily target") { amount = String(selection.habit.goal.target) }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(KeepButtonStyle(emphasis: .quiet))
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction).buttonStyle(KeepButtonStyle(emphasis: .primary))
            }
        }.padding(24).frame(width: 380).foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
    private func save() {
        guard let value = Int(amount), store.setAmount(value, habitID: selection.habit.id, on: selection.dayID, today: today) else {
            error = "Enter an amount from 0 to 1,000,000 for an active day."
            return
        }
        dismiss()
    }

}
