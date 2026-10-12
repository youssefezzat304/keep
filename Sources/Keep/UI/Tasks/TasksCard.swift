import SwiftUI

struct TasksCard: View {
    let workspace: WorkspaceModel?
    @Bindable var store: DailyTaskStore
    var today: Date = .now
    var canStartTimer: Bool
    var onStartTimer: ((FocusTask, WorkspaceModel.TaskTimers) -> Void)?
    @State private var selection = TaskDaySelection()
    @State private var drafts: [String: String] = [:]
    @State private var showsDatePicker = false
    @FocusState private var isAddingTask: Bool
    @FocusState private var isChoosingDay: Bool

    init(store: DailyTaskStore, today: Date = .now, initialDate: Date? = nil, canStartTimer: Bool = true,
         workspace: WorkspaceModel? = nil, onStartTimer: ((FocusTask, WorkspaceModel.TaskTimers) -> Void)? = nil) {
        self.workspace = workspace
        self.store = store
        self.today = today
        self.canStartTimer = canStartTimer
        self.onStartTimer = onStartTimer
        var selection = TaskDaySelection()
        if let initialDate { selection.select(initialDate, today: today, calendar: store.calendar) }
        _selection = State(initialValue: selection)
    }

    private var dayID: String { selection.dayID(today: today, calendar: store.calendar) }
    private var selectedDate: Date { selection.date(today: today, calendar: store.calendar) }
    private var isToday: Bool { dayID == TaskDay.id(for: today, calendar: store.calendar) }
    private var heading: String {
        if isToday { return "A few things for today" }
        let offset = store.calendar.dateComponents([.day], from: store.calendar.startOfDay(for: today), to: store.calendar.startOfDay(for: selectedDate)).day ?? 0
        if offset == -1 { return "A few things for yesterday" }
        if offset == 1 { return "A few things for tomorrow" }
        return "A few things for this day"
    }

    var body: some View {
        // Capture this rendered day for every action/binding; delayed input cannot target a newly selected day.
        let day = dayID
        let tasks = store.tasks(on: day)
        let draft = Binding(get: { drafts[day] ?? "" }, set: { drafts[day] = $0 })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading)
                    .font(KeepTheme.headingFont(size: 23))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(tasks.filter { !$0.isComplete }.count) left")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepTheme.mutedInk)
                    .fixedSize()
            }

            dayNavigation

            if let error = store.persistenceError ?? store.habitPersistenceError ?? store.habitStore?.recordingError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { workspace?.retryPersistence(); store.retryPersistence() }.font(.system(size: 12))
                }
                .padding(8)
                .background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 8))
            }

            Text(plannedSummary(tasks, today: isToday)).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { listArea in
                KeepScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks, id: \.listID) { task in
                            TaskRow(task: task, isComplete: Binding(
                                    get: { store.tasks(on: day).first { $0.id == task.id && $0.habitID == task.habitID }?.isComplete ?? task.isComplete },
                                    set: { store.setComplete($0, taskID: task.id, on: day, habitID: task.habitID, today: today) }
                                ), dayID: day, focusedSeconds: focusedSeconds(task, on: day), habitStore: store.habitStore,
                                onEdit: { title, estimate in
                                    if let workspace { try workspace.editTask(id: task.id, on: day, title: title, estimateMinutes: estimate) }
                                    else { try store.update(taskID: task.id, on: day, title: title, estimateMinutes: estimate) }
                                }, canComplete: store.canComplete(task, on: day, today: today), canStartTimer: canStartTimer, onStartTimer: timerAction(on: day)) {
                                    if let workspace { workspace.removeTask(task, on: day) }
                                    else { store.remove(taskID: task.id, on: day, habitID: task.habitID) }
                            }
                            .disabled(!store.canEdit)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 2)
                            .frame(minHeight: 44)
                            .overlay(alignment: .bottom) { rule }
                        }
                        if tasks.isEmpty && !store.loadFailed {
                            Text(isToday ? "A little space for your plans." : "No tasks planned for this day yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(KeepTheme.mutedInk)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .overlay(alignment: .bottom) { rule }
                        }
                        let occupied = tasks.isEmpty && !store.loadFailed ? 1 : tasks.count
                        let emptyRows = max(0, Int(listArea.size.height / 44) - occupied)
                        ForEach(0..<emptyRows, id: \.self) { _ in
                            Color.clear.frame(height: 44).overlay(alignment: .bottom) { rule }
                                .accessibilityHidden(true)
                        }
                    }
                }
                .id(day)
                .accessibilityLabel("Tasks for \(selectedDate.formatted(date: .long, time: .omitted))")
            }
            .frame(minHeight: 44)

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(KeepTheme.accentStrong)
                TextField("Add a little intention…", text: draft)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .focused($isAddingTask)
                    .onSubmit { addTask(on: day) }
                    .accessibilityLabel("New task for selected day")
                Button { addTask(on: day) } label: {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 12))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add task to selected day")
            }
            .disabled(!store.canEdit)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isAddingTask ? KeepTheme.focusRing : KeepTheme.border, lineWidth: isAddingTask ? 2 : 1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 288, maxHeight: .infinity)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
        }
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .environment(\.calendar, store.calendar)
        .environment(\.timeZone, store.calendar.timeZone)
        .onChange(of: dayID) { _, _ in isAddingTask = false }
    }

    private func focusedSeconds(_ task: FocusTask, on day: String) -> Double? {
        guard let workspace, workspace.canTrack else { return nil }
        return workspace.readIndex.focusedSeconds(task.habitID.map { .habit(id: $0) } ?? .task(id: task.id, dayID: day), on: day)
    }

    private func plannedSummary(_ tasks: [FocusTask], today: Bool) -> String {
        let planned = tasks.compactMap(\.estimateMinutes).reduce(0, +)
        let missing = tasks.filter { $0.habitID == nil && $0.estimateMinutes == nil }.count
        let duration = planned >= 60 ? "\(planned / 60) hr\(planned % 60 == 0 ? "" : " \(planned % 60) min")" : "\(planned) min"
        return "Planned \(today ? "today" : "for this day"): \(duration) · \(missing) \(missing == 1 ? "task" : "tasks") without estimates"
    }

    private var dayNavigation: some View {
        HStack(spacing: 6) {
            TaskDayButton(symbol: "chevron.left", label: "Previous day") { selection.move(by: -1, today: today, calendar: store.calendar) }
            Button { showsDatePicker.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar").foregroundStyle(KeepTheme.accentStrong)
                    Text(selectedDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 32)
            }
            .buttonStyle(TaskDateButtonStyle())
            .focused($isChoosingDay)
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(isChoosingDay ? KeepTheme.focusRing : .clear, lineWidth: 2) }
            .accessibilityLabel("Choose task day")
            .accessibilityValue(selectedDate.formatted(date: .complete, time: .omitted))
            .help("Choose any past or future day")
            .popover(isPresented: $showsDatePicker) {
                TaskDatePicker(date: selectedDate, calendar: store.calendar) { date in
                    selection.select(date, today: today, calendar: store.calendar)
                    showsDatePicker = false
                }
                .id(dayID)
            }
            TaskDayButton(symbol: "chevron.right", label: "Next day") { selection.move(by: 1, today: today, calendar: store.calendar) }
            Spacer(minLength: 0)
            Button("Today") { selection.goToToday() }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .disabled(isToday)
                .help("Return to today’s tasks")
        }
    }

    private var rule: some View { Rectangle().fill(KeepTheme.border).frame(height: 1) }

    private func timerAction(on day: String) -> ((FocusTask, WorkspaceModel.TaskTimers) -> Void)? {
        guard store.canStartTimers(on: day, today: today), let onStartTimer else { return nil }
        return { task, timers in
            // A day can change while a hover/control is still on screen.
            guard store.canStartTimers(on: day, today: .now), canStartTimer else { return }
            onStartTimer(task, timers)
        }
    }

    private func addTask(on day: String) {
        if store.add(drafts[day] ?? "", on: day) { drafts.removeValue(forKey: day) }
    }
}

private struct TaskRow: View {
    let task: FocusTask
    @Binding var isComplete: Bool
    let dayID: String
    let focusedSeconds: Double?
    let habitStore: HabitStore?
    let onEdit: (String, Int?) throws -> Void
    let canComplete: Bool
    let canStartTimer: Bool
    let onStartTimer: ((FocusTask, WorkspaceModel.TaskTimers) -> Void)?
    let onRemove: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Control?
    @Environment(\.self) private var environment
    @State private var showsEdit = false
    @State private var editHovered = false
    private enum Control: Hashable { case complete, focus, flow, both, edit, remove }
    private var timedHabit: Habit? { habitStore?.habits.first { $0.id == task.habitID && $0.goal.minuteTarget != nil } }

    var body: some View {
        HStack(spacing: 10) {
            if timedHabit != nil {
                Image(systemName: task.isComplete ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18)).frame(width: 18, height: 18)
                    .foregroundStyle(task.isComplete ? KeepTheme.accentStrong : KeepTheme.mutedInk)
                    .accessibilityLabel("\(task.title) habit goal").accessibilityValue(habitStore?.recordedDataAvailable == false ? "Recorded progress unavailable" : task.isComplete ? "Complete" : "In progress")
                    .help("Completed automatically from manual and recorded minutes")
            } else {
                Toggle("", isOn: $isComplete).labelsHidden().toggleStyle(KeepCheckboxStyle())
                    .focused($focused, equals: .complete)
                    .accessibilityLabel("Complete \(task.title)").disabled(!canComplete)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 13)).strikethrough(task.isComplete)
                if task.habitID == nil || timedHabit != nil {
                    Text("\(task.estimateMinutes.map { "Planned \($0) min" } ?? "Not estimated") · Focused \(focusedSeconds.map { TaskTimeTotals.minutesLabel(seconds: $0) } ?? "—")")
                        .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                }
                if let habit = timedHabit, let habitStore {
                    let manual = habitStore.manualAmount(habitID: habit.id, on: dayID)
                    Text("Habit \(habitStore.recordedDataAvailable ? String(habitStore.amount(for: habit, on: dayID)) : "—")/\(habit.goal.target) min\(manual > 0 ? " · Manual \(manual) min" : "")")
                        .font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
                } else if task.habitID != nil { Text("Habit").font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk) }
            }
                .foregroundStyle(task.isComplete ? KeepTheme.mutedInk : KeepTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2).help(task.title)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(task.title)
                .accessibilityValue(accessibleProgress)
                .accessibilityActions {
                    if let onStartTimer, canStartTimer {
                        Button("Start Focus") { onStartTimer(task, .focus) }
                        Button("Start Flow") { onStartTimer(task, .flow) }
                        Button("Start both timers") { onStartTimer(task, .both) }
                    }
                }
            if let onStartTimer {
                HStack(spacing: 4) {
                    timerButton(.focus, label: "Start Focus", control: .focus,
                        fill: KeepTheme.timerSurface(mode: .pomodoro, environment: environment), ink: KeepTheme.ink, action: onStartTimer)
                    timerButton(.flow, label: "Start Flow", control: .flow,
                        fill: KeepTheme.timerSurface(mode: .flow, environment: environment), ink: KeepTheme.ink, action: onStartTimer)
                    timerButton(.both, label: "Start both timers", control: .both,
                        fill: KeepTheme.taskBothTimerFill, ink: KeepTheme.taskBothTimerInk, action: onStartTimer)
                }
                .opacity(hovered || focused != nil ? 1 : 0)
                .allowsHitTesting(hovered || focused != nil)
            }
            Button { showsEdit = true } label: { Image(systemName: "pencil").frame(width: 24, height: 30)
                    .background(editHovered ? KeepTheme.mutedWarm.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 6)) }
                .buttonStyle(.plain).onHover { editHovered = $0 }.focused($focused, equals: .edit)
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(focused == .edit ? KeepTheme.focusRing : .clear, lineWidth: 2) }
                .accessibilityLabel("\(task.habitID == nil ? "Edit task" : "Edit habit progress"): \(task.title)")
                .help(task.habitID == nil ? "Edit task and estimate" : "Edit manually logged habit progress")
                .popover(isPresented: $showsEdit) {
                    if let habitID = task.habitID, let habitStore, let habit = habitStore.habits.first(where: { $0.id == habitID }) {
                        HabitAmountDialog(selection: HabitLogSelection(habit: habit, dayID: dayID), store: habitStore, today: .now)
                    } else if task.habitID == nil { TaskEstimateEditor(task: task, onSave: onEdit) }
                }
            RemoveRowButton(label: "Delete task: \(task.title)", action: onRemove)
                .focused($focused, equals: .remove)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu { Button(task.habitID == nil ? "Edit task…" : "Edit habit progress…") { showsEdit = true } }
    }

    private var accessibleProgress: String {
        guard task.habitID == nil || timedHabit != nil else { return "Habit" }
        let comparison = "\(task.estimateMinutes.map { "Planned \($0) minutes" } ?? "Not estimated"), focused \(focusedSeconds.map { TaskTimeTotals.minutesLabel(seconds: $0) } ?? "time unavailable")"
        guard let habit = timedHabit, let habitStore else { return comparison }
        guard habitStore.recordedDataAvailable else { return comparison + ", recorded habit progress unavailable" }
        return comparison + ", habit progress \(habitStore.amount(for: habit, on: dayID)) of \(habit.goal.target) minutes, manual \(habitStore.manualAmount(habitID: habit.id, on: dayID)) minutes"
    }

    private func timerButton(_ timers: WorkspaceModel.TaskTimers, label: String, control: Control,
                             fill: Color, ink: Color, action: @escaping (FocusTask, WorkspaceModel.TaskTimers) -> Void) -> some View {
        Button { action(task, timers) } label: {
            Image(systemName: "play.fill").font(.system(size: 11))
                .offset(x: 1)
                .foregroundStyle(ink).frame(width: 30, height: 30)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).focusable().focused($focused, equals: control).focusEffectDisabled().disabled(!canStartTimer)
        .onKeyPress(keys: [.space, .return]) { _ in
            guard canStartTimer, environment.isEnabled else { return .ignored }
            action(task, timers)
            return .handled
        }
        .overlay { Circle().strokeBorder(focused == control ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
        .accessibilityLabel("\(label) for \(task.title)").help("\(label) for this task")
    }
}

private struct TaskDateButtonStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(KeepTheme.ink)
            .background(KeepTheme.mutedWarm.opacity(configuration.isPressed ? 0.9 : hovered ? 0.75 : 0.5), in: RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}

private struct TaskDayButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 32, height: 32)
                .background(KeepTheme.mutedWarm.opacity(hovered ? 0.65 : 0.25), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .focused($focused)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2) }
        .accessibilityLabel(label)
        .help(label)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date.now
    TasksCard(store: DailyTaskStore(archive: TaskArchive(days: [TaskDay.id(for: today, calendar: calendar): FocusTask.examples])), today: today)
        .padding().frame(width: 450, height: 430).background(KeepTheme.paper)
}
