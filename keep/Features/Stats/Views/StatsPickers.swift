import SwiftUI

struct StatsDateRangePicker: View {
    let calendar: Calendar
    let now: Date
    let onApply: (Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var choosingStart = false
    @State private var choosingEnd = false

    init(range: StatsRange, calendar: Calendar, now: Date, onApply: @escaping (Date, Date) -> Void) {
        self.calendar = calendar; self.now = now; self.onApply = onApply
        _start = State(initialValue: range.start)
        _end = State(initialValue: min(range.endDay(calendar: calendar), now))
    }
    private var valid: Bool { calendar.startOfDay(for: start) <= calendar.startOfDay(for: end) && calendar.startOfDay(for: end) <= calendar.startOfDay(for: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose your dates").font(KeepTheme.headingFont(size: 26))
            dateButton("Start", date: start) { choosingStart = true }
                .popover(isPresented: $choosingStart) {
                    TaskDatePicker(date: start, calendar: calendar, confirmationTitle: "Choose start") { start = $0; choosingStart = false }
                }
            dateButton("End", date: end) { choosingEnd = true }
                .popover(isPresented: $choosingEnd) {
                    TaskDatePicker(date: end, calendar: calendar, confirmationTitle: "Choose end") { end = $0; choosingEnd = false }
                }
            Text(valid ? "Both dates are included." : "Choose an end on or after the start, no later than today.")
                .font(.system(size: 13)).foregroundStyle(valid ? KeepTheme.mutedInk : KeepTheme.accentStrong)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply(start, end); dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .padding(24).frame(width: 360).background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
    }
    private func dateButton(_ title: String, date: Date, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))); Image(systemName: "calendar") }
        }
        .buttonStyle(KeepButtonStyle(emphasis: .quiet)).accessibilityLabel("\(title) date")
        .accessibilityValue(date.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)))
    }
}

struct StatsTaskPicker: View {
    let options: [StatsModel.TaskOption]
    let onApply: (Set<String>?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var all: Bool
    @State private var search = ""

    init(options: [StatsModel.TaskOption], selection: Set<String>?, onApply: @escaping (Set<String>?) -> Void) {
        self.options = options; self.onApply = onApply
        _selected = State(initialValue: selection ?? [])
        _all = State(initialValue: selection == nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose tasks").font(KeepTheme.headingFont(size: 25))
            TextField("Search tasks", text: $search).modifier(KeepInputStyle())
            Toggle("All tasks", isOn: $all)
            KeepScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(options.filter { search.isEmpty || $0.name.localizedStandardContains(search) }) { task in
                        Toggle(task.name, isOn: Binding(get: { !all && selected.contains(task.id) }, set: { checked in
                            all = false
                            if checked { selected.insert(task.id) } else { selected.remove(task.id) }
                        }))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if options.isEmpty { Text("No recorded tasks in this project yet.").foregroundStyle(KeepTheme.mutedInk) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }.frame(height: 230)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply(all ? nil : selected); dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction).disabled(!all && selected.isEmpty)
            }
        }.padding(24).frame(width: 360).background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
    }
}

struct StatsGoalEditor: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var hours: String
    @State private var minutes: String
    init(preferences: AppPreferences) {
        self.preferences = preferences
        _hours = State(initialValue: preferences.weeklyFocusGoalMinutes.map { String($0 / 60) } ?? "0")
        _minutes = State(initialValue: preferences.weeklyFocusGoalMinutes.map { String($0 % 60) } ?? "0")
    }
    private var value: Int? {
        guard let hours = Int(hours), let minutes = Int(minutes), (0...168).contains(hours), (0...59).contains(minutes),
              (1...10080).contains(hours * 60 + minutes) else { return nil }
        return hours * 60 + minutes
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A weekly focus goal").font(KeepTheme.headingFont(size: 26))
            Text("For all projects, Monday to Sunday.").foregroundStyle(KeepTheme.mutedInk)
            HStack {
                VStack(alignment: .leading) { Text("Hours"); TextField("0", text: $hours).modifier(KeepInputStyle()).accessibilityLabel("Weekly goal hours") }
                VStack(alignment: .leading) { Text("Minutes"); TextField("0", text: $minutes).modifier(KeepInputStyle()).accessibilityLabel("Weekly goal minutes") }
            }
            Text("Choose between 1 minute and 168 hours.").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if preferences.weeklyFocusGoalMinutes != nil {
                    Button("Remove goal") { preferences.weeklyFocusGoalMinutes = nil; dismiss() }.foregroundStyle(KeepTheme.accentStrong).disabled(!preferences.canEdit)
                }
                Spacer()
                Button("Save") { if let value { preferences.weeklyFocusGoalMinutes = value; dismiss() } }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction).disabled(value == nil || !preferences.canEdit)
            }
        }.padding(24).frame(width: 420).background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
    }
}
