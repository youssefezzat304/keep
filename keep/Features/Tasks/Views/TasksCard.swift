import SwiftUI

struct TasksCard: View {
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
         onStartTimer: ((FocusTask, WorkspaceModel.TaskTimers) -> Void)? = nil) {
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
                    .font(.system(size: 23, design: .serif))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(tasks.filter { !$0.isComplete }.count) left")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepTheme.mutedInk)
                    .fixedSize()
            }

            dayNavigation

            if let error = store.persistenceError ?? store.habitPersistenceError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { store.retryPersistence() }.font(.system(size: 12))
                }
                .padding(8)
                .background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 8))
            }

            GeometryReader { listArea in
                KeepScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks, id: \.listID) { task in
                            TaskRow(task: task, isComplete: Binding(
                                    get: { store.tasks(on: day).first { $0.id == task.id && $0.habitID == task.habitID }?.isComplete ?? task.isComplete },
                                    set: { store.setComplete($0, taskID: task.id, on: day, habitID: task.habitID, today: today) }
                                ), canComplete: store.canComplete(task, on: day, today: today), canStartTimer: canStartTimer, onStartTimer: timerAction(on: day)) {
                                    store.remove(taskID: task.id, on: day, habitID: task.habitID)
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
    let canComplete: Bool
    let canStartTimer: Bool
    let onStartTimer: ((FocusTask, WorkspaceModel.TaskTimers) -> Void)?
    let onRemove: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Control?
    @Environment(\.self) private var environment
    private enum Control: Hashable { case complete, focus, flow, both, remove }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isComplete).labelsHidden().toggleStyle(KeepCheckboxStyle())
                .focused($focused, equals: .complete)
                .accessibilityLabel("Complete \(task.title)").disabled(!canComplete)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 13)).strikethrough(task.isComplete)
                if task.habitID != nil { Text("Habit").font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk) }
            }
                .foregroundStyle(task.isComplete ? KeepTheme.mutedInk : KeepTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2).help(task.title)
                .accessibilityLabel(task.title)
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
            RemoveRowButton(label: "Delete task: \(task.title)", action: onRemove)
                .focused($focused, equals: .remove)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
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
