import SwiftUI

struct TaskDatePicker: View {
    @State private var date: Date
    @State private var month: Date
    @State private var typedDate: String
    @FocusState private var focusedDay: String?
    @FocusState private var typingDate: Bool
    let calendar: Calendar
    let onChoose: (Date) -> Void

    init(date: Date, calendar: Calendar, onChoose: @escaping (Date) -> Void) {
        _date = State(initialValue: date)
        _month = State(initialValue: date)
        _typedDate = State(initialValue: TaskDay.id(for: date, calendar: calendar))
        self.calendar = calendar
        self.onChoose = onChoose
    }

    private var grid: TaskMonthGrid { TaskMonthGrid(month: month, calendar: calendar) }
    private var enteredDate: Date? { TaskDay.date(for: typedDate, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a day").font(.system(size: 25, design: .serif))
            HStack {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                monthButton("chevron.left", label: "Previous month", offset: -1)
                monthButton("chevron.right", label: "Next month", offset: 1)
            }

            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    ForEach(Array(grid.weekdays.enumerated()), id: \.offset) { _, day in
                        Text(day.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.5)
                            .foregroundStyle(KeepTheme.mutedInk)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
                    ForEach(grid.days, id: \.self) { day in
                        dayButton(day)
                    }
                }
            }
            Rectangle().fill(KeepTheme.border).frame(height: 1)
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(KeepTheme.accentStrong)
                TextField("YYYY-MM-DD", text: $typedDate)
                    .modifier(KeepInputStyle())
                    .focused($typingDate)
                    .accessibilityLabel("Jump to date, year-month-day")
                    .onSubmit {
                        if let enteredDate { select(enteredDate) }
                    }
            }
            if enteredDate == nil {
                Text("Enter a date as YYYY-MM-DD.")
                    .font(.system(size: 11)).foregroundStyle(KeepTheme.accentStrong)
            }
            HStack {
                Button("Today") { select(Date.now) }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                Spacer()
                Button("Show tasks") {
                    if let enteredDate { onChoose(enteredDate) }
                }
                .buttonStyle(KeepButtonStyle(emphasis: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(enteredDate == nil)
            }
        }
        .padding(22).frame(width: 336)
        .background(KeepTheme.surface)
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .onAppear { focusedDay = TaskDay.id(for: date, calendar: calendar) }
    }

    private func monthButton(_ symbol: String, label: String, offset: Int) -> some View {
        Button { month = grid.moving(by: offset) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(KeepButtonStyle(emphasis: .quiet))
        .accessibilityLabel(label).help(label)
    }

    private func dayButton(_ day: Date) -> some View {
        let id = TaskDay.id(for: day, calendar: calendar)
        let selected = calendar.isDate(day, inSameDayAs: date)
        let today = calendar.isDateInToday(day)
        return Button { select(day) } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: selected || today ? .semibold : .regular))
                Circle().fill(today ? (selected ? KeepTheme.surface : KeepTheme.accentStrong) : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity).frame(height: 34)
        }
        .buttonStyle(CalendarDayStyle(selected: selected, inMonth: grid.contains(day)))
        .focusable().focusEffectDisabled()
        .focused($focusedDay, equals: id)
        .onMoveCommand { direction in moveFocus(from: day, direction: direction) }
        .accessibilityLabel(day.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)))
        .accessibilityValue(today ? "Today" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ value: Date) {
        date = value
        month = value
        typedDate = TaskDay.id(for: value, calendar: calendar)
    }

    private func moveFocus(from day: Date, direction: MoveCommandDirection) {
        let offset: Int
        switch direction {
        case .left: offset = -1
        case .right: offset = 1
        case .up: offset = -7
        case .down: offset = 7
        @unknown default: return
        }
        guard let next = calendar.date(byAdding: .day, value: offset, to: day) else { return }
        if !grid.days.contains(where: { calendar.isDate($0, inSameDayAs: next) }) { month = next }
        focusedDay = TaskDay.id(for: next, calendar: calendar)
    }
}

private struct CalendarDayStyle: ButtonStyle {
    let selected: Bool
    let inMonth: Bool
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? KeepTheme.surface : inMonth ? KeepTheme.ink : KeepTheme.mutedInk)
            .background(selected ? KeepTheme.accentStrong : hovered ? KeepTheme.mutedWarm : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2) }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hovered = $0 }
    }
}

#Preview("Calendar") {
    TaskDatePicker(date: .now, calendar: .current) { _ in }
}
