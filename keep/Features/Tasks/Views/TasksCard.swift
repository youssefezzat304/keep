import SwiftUI

struct TasksCard: View {
    @Bindable var store: DailyTaskStore
    var today: Date = .now
    @State private var selection = TaskDaySelection()
    @State private var drafts: [String: String] = [:]
    @State private var showsDatePicker = false
    @FocusState private var isAddingTask: Bool
    @FocusState private var isChoosingDay: Bool

    init(store: DailyTaskStore, today: Date = .now, initialDate: Date? = nil) {
        self.store = store
        self.today = today
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

            if let error = store.persistenceError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { store.retryPersistence() }.font(.system(size: 12))
                }
                .padding(8)
                .background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 8))
            }

            GeometryReader { listArea in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks) { task in
                            HStack(spacing: 14) {
                                Toggle("", isOn: Binding(
                                    get: { store.tasks(on: day).first { $0.id == task.id }?.isComplete ?? task.isComplete },
                                    set: { store.setComplete($0, taskID: task.id, on: day) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Complete \(task.title)")
                                Text(task.title)
                                    .font(.system(size: 13))
                                    .strikethrough(task.isComplete)
                                    .foregroundStyle(task.isComplete ? KeepTheme.mutedInk : KeepTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(2)
                                    .help(task.title)
                                RemoveRowButton(label: "Delete task: \(task.title)") {
                                    store.remove(taskID: task.id, on: day)
                                }
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
                .scrollIndicators(.hidden)
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

    private func addTask(on day: String) {
        if store.add(drafts[day] ?? "", on: day) { drafts.removeValue(forKey: day) }
    }
}

struct TaskDatePicker: View {
    @State var date: Date
    let calendar: Calendar
    let onChoose: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a day").font(.system(size: 20, design: .serif))
            DatePicker("Task day", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .accessibilityLabel("Task day")
                .frame(maxWidth: .infinity, alignment: .center)
            DatePicker("Date", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.field)
                .accessibilityLabel("Type a specific task date")
            HStack {
                Spacer()
                Button("Show tasks") { onChoose(date) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 300)
        .background(KeepTheme.surface)
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
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
