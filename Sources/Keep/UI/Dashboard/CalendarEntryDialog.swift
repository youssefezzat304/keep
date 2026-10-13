import SwiftUI

struct CalendarEntryDialog: View {
    let workspace: WorkspaceModel
    let onAdded: (RecordedSession) -> Void
    @State private var draft: CalendarEntryDraft
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(workspace: WorkspaceModel, initialDate: Date, onAdded: @escaping (RecordedSession) -> Void = { _ in }) {
        self.workspace = workspace
        self.onAdded = onAdded
        _draft = State(initialValue: CalendarEntryDraft(projectID: workspace.selectedProject?.id ?? FocusProject.unassigned.id, date: initialDate))
    }
    private var validName: Bool { draft.task.trimmingCharacters(in: .whitespacesAndNewlines).count <= 200 }
    private var availableTasks: [FocusTask] { workspace.entryTasks(on: draft.date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add an entry").font(KeepTheme.headingFont(size: 27))
            Text("A little time you’ve already spent.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            VStack(alignment: .leading, spacing: 7) {
                Text("Project").font(.system(size: 12, weight: .medium))
                Picker("Project", selection: $draft.projectID) {
                    Text("No project").tag(FocusProject.unassigned.id)
                    ForEach(workspace.projects) { project in Text(project.name).tag(project.id) }
                }.labelsHidden().accessibilityLabel("Entry project")
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Task name").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 8)
                    if !availableTasks.isEmpty {
                        Menu("Use a saved task…") {
                            ForEach(availableTasks) { task in
                                Button(choiceLabel(task)) {
                                    draft.task = task.title
                                    draft.reference = task.habitID.map { .habit(id: $0) } ?? .task(id: task.id, dayID: TaskDay.id(for: draft.date, calendar: workspace.calendar))
                                }
                            }
                        }.font(.system(size: 12)).accessibilityLabel("Choose a saved task or habit for this date")
                    }
                }
                TextField("Unnamed task", text: $draft.task).modifier(KeepInputStyle())
                    .accessibilityLabel("Entry task name").onSubmit(add)
                    .onChange(of: draft.task) { _, name in
                        if let reference = draft.reference,
                           !availableTasks.contains(where: { $0.id == reference.id && $0.title == name }) { draft.reference = nil }
                    }
                if !validName { Text("Use 200 characters or fewer.").font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong) }
                if draft.reference != nil {
                    HStack {
                        Text("Linked to the selected task or habit").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                        Spacer(minLength: 4)
                        Button("Unlink") { draft.reference = nil }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
                    }
                }
            }
            DatePicker("Date", selection: $draft.date, in: Date.distantPast...Date.now, displayedComponents: .date)
                .datePickerStyle(.field).font(.system(size: 13)).accessibilityLabel("Entry date")
                .onChange(of: draft.date) { draft.reference = nil; error = nil }
            HStack(spacing: 14) {
                timeField("Start", value: $draft.startTime)
                timeField("End", value: $draft.endTime)
            }
            Text("HH:mm:ss · \(workspace.calendar.timeZone.identifier) · 24:00 ends at midnight")
                .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            Text("Added time counts in Calendar, Timesheet and Stats. Choose a saved task to credit its tracked time.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add entry", action: add).buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction)
                    .disabled(!workspace.canTrack || !validName)
            }
        }.padding(28).frame(width: 420).background(KeepTheme.surface).foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
            .environment(\.calendar, workspace.calendar).environment(\.timeZone, workspace.calendar.timeZone)
    }
    private func choiceLabel(_ task: FocusTask) -> String {
        var details = task.habitID == nil ? "Task" : "Habit"
        if availableTasks.filter({ StatsQuery.taskKey($0.title) == StatsQuery.taskKey(task.title) }).count > 1 {
            details += " · " + (task.estimateMinutes.map { "\($0) min" } ?? "Not estimated") + " · " + String(task.id.uuidString.prefix(8))
        }
        return task.title + " · " + details
    }

    private func timeField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextField("HH:mm:ss", text: value).modifier(KeepInputStyle()).monospacedDigit()
                .accessibilityLabel("Entry \(title.lowercased()) time").onSubmit(add)
        }
    }
    private func add() {
        guard workspace.canTrack, validName else { return }
        do { let entry = try workspace.addCalendarEntry(draft); onAdded(entry); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
