import SwiftUI

struct CalendarEntryDialog: View {
    let workspace: WorkspaceModel
    let onAdded: (RecordedSession) -> Void
    @State private var draft: CalendarEntryDraft
    @State private var error: String?
    @State private var choosingProject = false
    @State private var choosingDate = false
    @State private var choosingTask = false
    @State private var taskSearchName = ""
    @FocusState private var focused: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment
    private enum Field: Hashable { case project, task, date }

    init(workspace: WorkspaceModel, initialDate: Date, initialProjectID: String? = nil, onAdded: @escaping (RecordedSession) -> Void = { _ in }) {
        self.workspace = workspace
        self.onAdded = onAdded
        _draft = State(initialValue: CalendarEntryDraft(projectID: initialProjectID ?? workspace.selectedProject?.id ?? FocusProject.unassigned.id, date: initialDate))
    }
    private var validName: Bool { draft.task.trimmingCharacters(in: .whitespacesAndNewlines).count <= 200 }
    private var project: FocusProject { workspace.projects.first { $0.id == draft.projectID } ?? .unassigned }
    private var suggestions: [CalendarEntryTaskSuggestion] { workspace.entryTaskSuggestions(on: draft.date, projectID: draft.projectID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add an entry").font(KeepTheme.headingFont(size: 27))
            Text("A little time you’ve already spent.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            projectSelection
            taskSelection
            dateSelection
            HStack(spacing: 14) {
                timeField("Start", value: $draft.startTime)
                timeField("End", value: $draft.endTime)
            }
            Text("HH:mm:ss · \(workspace.calendar.timeZone.identifier) · 24:00 ends at midnight")
                .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add entry", action: add).buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction)
                    .disabled(!workspace.canTrack || !validName)
            }
        }.padding(28).frame(width: 420).background(KeepTheme.surface).foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
            .environment(\.calendar, workspace.calendar).environment(\.timeZone, workspace.calendar.timeZone)
            .onChange(of: draft.task) { _, name in
                if let reference = draft.reference, !suggestions.contains(where: { $0.reference == reference && $0.title == name }) { draft.reference = nil }
            }
            .onChange(of: draft.date) { draft.reference = nil; error = nil }
    }
    private var projectSelection: some View {
        Button { choosingProject = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.system(size: 21)).foregroundStyle(project.labelColor(in: environment))
                    .frame(width: 46, height: 46).background(project.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("WORKING ON").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(KeepTheme.mutedInk)
                    Text(project.name).font(.system(size: 13, weight: .medium)).foregroundStyle(project.labelColor(in: environment)).lineLimit(1)
                    Text(project.category).font(.system(size: 14, weight: .medium)).foregroundStyle(KeepTheme.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(focused == .project ? KeepTheme.focusRing : KeepTheme.border, lineWidth: focused == .project ? 2 : 1).allowsHitTesting(false) }
        }.buttonStyle(.plain).focused($focused, equals: .project)
            .accessibilityLabel("Entry project").accessibilityValue(project.name).help("Choose a project")
            .popover(isPresented: $choosingProject) {
                ProjectPicker(projects: workspace.projects, selectedProject: project.id == FocusProject.unassigned.id ? nil : project, showsCreation: false) { selected in
                    draft.projectID = selected?.id ?? FocusProject.unassigned.id
                    choosingProject = false; focused = .project
                }.onExitCommand { choosingProject = false }
            }
    }
    private var taskSelection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Task name").font(.system(size: 12, weight: .medium))
            Button { taskSearchName = draft.task; choosingTask = true } label: {
                HStack {
                    Text(draft.task.isEmpty ? "Search or name a task" : draft.task)
                        .font(.system(size: 13)).foregroundStyle(draft.task.isEmpty ? KeepTheme.mutedInk : KeepTheme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                }.padding(.horizontal, 12).frame(minHeight: 36).background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused == .task ? KeepTheme.focusRing : KeepTheme.border, lineWidth: focused == .task ? 2 : 1).allowsHitTesting(false) }
            }.buttonStyle(.plain).focused($focused, equals: .task)
                .accessibilityLabel("Entry task name").accessibilityValue(draft.task.isEmpty ? "Unnamed task" : draft.task).help("Search tasks or enter a new name")
                .popover(isPresented: $choosingTask) {
                    CalendarEntryTaskPicker(name: $taskSearchName, suggestions: suggestions, onSelect: { suggestion in
                        taskSearchName = suggestion.title
                        draft.task = suggestion.title; draft.reference = suggestion.reference
                        choosingTask = false; focused = .task
                    }, onUseName: {
                        draft.task = taskSearchName; draft.reference = nil
                        choosingTask = false; focused = .task
                    }, onClose: { commitTaskSearch(); choosingTask = false; focused = .task })
                        .onDisappear { commitTaskSearch() }
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
    }
    private var dateSelection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Date").font(.system(size: 12, weight: .medium))
            Button { choosingDate = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar").foregroundStyle(KeepTheme.accentStrong)
                    Text(draft.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: workspace.calendar, timeZone: workspace.calendar.timeZone))
                        .font(.system(size: 13)).foregroundStyle(KeepTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                }.padding(.horizontal, 12).frame(minHeight: 36).background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused == .date ? KeepTheme.focusRing : KeepTheme.border, lineWidth: focused == .date ? 2 : 1).allowsHitTesting(false) }
            }.buttonStyle(.plain).focused($focused, equals: .date).accessibilityLabel("Entry date")
                .accessibilityValue(TaskDay.id(for: draft.date, calendar: workspace.calendar))
                .popover(isPresented: $choosingDate) {
                    TaskDatePicker(date: draft.date, calendar: workspace.calendar, confirmationTitle: "Use date", latestDate: .now) { date in
                        draft.date = date; choosingDate = false; focused = .date
                    }.onExitCommand { choosingDate = false }
                }
        }
    }
    private func commitTaskSearch() {
        if draft.task != taskSearchName { draft.task = taskSearchName; draft.reference = nil }
    }
    private func timeField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextField("HH:mm:ss", text: value).modifier(KeepInputStyle()).monospacedDigit()
                .accessibilityLabel("Entry \(title.lowercased()) time").onSubmit(add)
        }
    }
    private func add() {
        if choosingTask { commitTaskSearch() }
        guard workspace.canTrack, validName else { return }
        do { let entry = try workspace.addCalendarEntry(draft); onAdded(entry); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
