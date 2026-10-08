import SwiftUI

struct StatsView: View {
    let workspace: WorkspaceModel
    let tasks: DailyTaskStore
    let habits: HabitStore
    @Bindable var preferences: AppPreferences
    let isVisible: Bool
    @State private var model = StatsModel()
    @State private var showsDates = false
    @State private var showsProjects = false
    @State private var showsTasks = false
    @State private var showsGoal = false
    @Environment(\.self) private var environment
    @State private var goalProject: FocusProject?

    init(workspace: WorkspaceModel, tasks: DailyTaskStore, habits: HabitStore, preferences: AppPreferences, isVisible: Bool, initialQuery: StatsQuery = StatsQuery()) {
        self.workspace = workspace; self.tasks = tasks; self.habits = habits
        self.preferences = preferences; self.isVisible = isVisible
        _model = State(initialValue: StatsModel(query: initialQuery))
    }

    private var calendar: Calendar { StatsSnapshot.calendar(workspace.calendar) }
    private var range: StatsRange { model.query.range(now: .now, calendar: calendar) }

    var body: some View {
        // Measure the proposed viewport, never the content that uses this width.
        // Native scrollbar insets otherwise create a self-expanding layout loop.
        GeometryReader { viewport in
            VStack(alignment: .leading, spacing: 20) {
                header
                KeepScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = model.calculationError {
                            issue(error) { refresh() }
                        }
                        if let snapshot = model.snapshot {
                            if workspace.canTrack {
                                focusContent(snapshot, contentWidth: viewport.size.width)
                                goal(snapshot)
                            } else {
                                issue("Your focus history couldn’t be loaded.") { workspace.retryPersistence(); refresh() }
                            }
                            habitsContent(snapshot)
                            tasksContent(snapshot)
                            if let error = preferences.persistenceError { issue(error) { preferences.retryPersistence() } }
                            streaks(snapshot)
                        } else if model.calculationError == nil {
                            ProgressView("Preparing your statistics…").padding(32).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
        }
        .foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
        .task(id: isVisible) { if isVisible { refresh() } else { model.cancel() } }
        .onChange(of: model.query) { _, _ in refresh() }
        .onChange(of: workspace.displayInstant) { _, _ in refresh() }
        .onChange(of: tasks.revision) { _, _ in refresh() }
        .onChange(of: habits.revision) { _, _ in refresh() }
        .onChange(of: workspace.readIndex.revision) { _, _ in refresh() }
        .onChange(of: workspace.loadFailed) { _, _ in refresh() }
        .onDisappear { model.cancel() }
        .popover(isPresented: $showsDates) {
            StatsDateRangePicker(range: range, calendar: calendar, now: .now) { start, end in
                model.query.customStart = start; model.query.customEnd = end; model.query.period = .custom; model.query.anchor = nil
            }
        }
        .popover(isPresented: $showsTasks) {
            StatsTaskPicker(options: model.taskOptions, selection: model.query.taskKeys) { model.query.taskKeys = $0 }
        }
        .popover(isPresented: $showsProjects) {
            StatsProjectPicker(options: model.projects, selection: model.query.projectID) { projectID in
                if model.query.projectID != projectID {
                    model.query.projectID = projectID
                    model.query.taskKeys = nil
                }
            }
        }
        .sheet(item: $goalProject) { project in ProjectGoalsDialog(workspace: workspace, project: project) }
        .sheet(isPresented: $showsGoal) { StatsGoalEditor(preferences: preferences) }
    }

    private func refresh() {
        guard isVisible else { return }
        model.refresh(workspace: workspace, tasks: tasks, habits: habits)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A little perspective.").font(KeepTheme.headingFont(size: 36))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { periodPicker; Spacer(minLength: 0); dateNavigation }
                VStack(alignment: .leading, spacing: 12) { periodPicker; dateNavigation }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { projectPicker; taskPicker; clearFilters }
                VStack(alignment: .leading, spacing: 10) { projectPicker; HStack { taskPicker; clearFilters } }
            }
        }
    }
    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(StatsPeriod.allCases, id: \.self) { period in
                Button(period.title) {
                    if period == .custom { showsDates = true }
                    else { model.query.period = period; model.query.anchor = nil }
                }
                .buttonStyle(KeepButtonStyle(emphasis: model.query.period == period ? .primary : .quiet))
                .accessibilityAddTraits(model.query.period == period ? .isSelected : [])
            }
        }.padding(4).background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private var dateNavigation: some View {
        HStack(spacing: 6) {
            Button { model.query.move(-1, now: .now, calendar: calendar) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous period")
            Button { showsDates = true } label: { Text(range.title(calendar: calendar)).font(.system(size: 12)).lineLimit(1) }
                .accessibilityLabel("Choose custom dates, \(range.title(calendar: calendar))")
            Button { model.query.move(1, now: .now, calendar: calendar) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next period")
                .disabled(!canMoveForward)
            if model.query.anchor != nil || model.query.period == .custom {
                Button { model.query.anchor = nil; model.query.period = .week } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("Return to this week").help("This week")
            }
        }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).fixedSize(horizontal: true, vertical: false)
    }
    private var canMoveForward: Bool {
        var next = model.query
        next.move(1, now: .now, calendar: calendar)
        return next != model.query
    }
    private var projectPicker: some View {
        Button { showsProjects = true } label: {
            Label(model.projects.first { $0.id == model.query.projectID }.map { $0.name + ($0.deleted ? " (Deleted)" : "") } ?? "All projects", systemImage: "folder")
                .lineLimit(1)
        }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).accessibilityLabel("Filter by project")
    }
    private var taskPicker: some View {
        Button { showsTasks = true } label: {
            Label(model.query.taskKeys.map { "\($0.count) \($0.count == 1 ? "task" : "tasks") selected" } ?? "All tasks", systemImage: "checklist")
        }
        .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(model.query.projectID == nil)
        .help(model.query.projectID == nil ? "Choose a project to filter its recorded tasks" : "Choose recorded task names")
    }
    @ViewBuilder private var clearFilters: some View {
        if model.query.projectID != nil {
            Button("Clear filters") { model.query.projectID = nil; model.query.taskKeys = nil }
                .buttonStyle(KeepButtonStyle(emphasis: .quiet))
        }
    }

    private func focusContent(_ snapshot: StatsSnapshot, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            card { StatsActivityGrid(snapshot: snapshot.focusActivity, availableWidth: contentWidth) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: contentWidth >= 820 ? 4 : 2), spacing: 16) {
                metric("Focus time", value: TimesheetDuration.total(snapshot.total), detail: "Recorded sessions", fill: KeepTheme.sage)
                metric("Active days", value: "\(snapshot.activeDays)", detail: "Days with recorded focus", fill: KeepTheme.mistBlue)
                metric("Daily average", value: TimesheetDuration.total(snapshot.average), detail: "Per active day", fill: KeepTheme.highlight)
                metric("Pomodoros", value: snapshot.pomodorosAvailable ? "\(snapshot.pomodoros)" : "Unavailable", detail: "Completed focus intervals", fill: KeepTheme.surface)
            }
            VStack(alignment: .leading, spacing: 8) {
                let difference = snapshot.total - snapshot.previousTotal
                Text(difference == 0 ? "The same focus time as the previous equivalent period" : "\(TimesheetDuration.total(abs(difference))) \(difference < 0 ? "less" : "more") than the previous equivalent period")
                    .font(.system(size: 14, weight: .medium))
            }
            if contentWidth >= 1100 {
                HStack(alignment: .top, spacing: 20) {
                    trend(snapshot, height: 390).frame(width: (contentWidth - 20) * 2 / 3)
                    card { distribution(snapshot, compact: true) }.frame(width: (contentWidth - 20) / 3)
                }
            } else {
                trend(snapshot, height: 250)
                card { distribution(snapshot) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    weekdayChart(snapshot).frame(minWidth: 330)
                    hourChart(snapshot).frame(minWidth: 330)
                }
                VStack(spacing: 20) { weekdayChart(snapshot); hourChart(snapshot) }
            }
        }
    }
    private func trend(_ snapshot: StatsSnapshot, height: CGFloat) -> some View {
        card {
            StatsBarChart(title: "Your focus over time", points: snapshot.buckets.enumerated().map {
                .init(id: $0.offset, label: $0.element.label, seconds: $0.element.seconds)
            }, plotHeight: height)
            if snapshot.total == 0 { Text("No recorded focus matches these dates and filters.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk) }
        }
    }
    private func weekdayChart(_ snapshot: StatsSnapshot) -> some View {
        card {
            StatsBarChart(title: "Focus by weekday", points: snapshot.weekdays.enumerated().map {
                .init(id: $0.offset, label: calendar.shortWeekdaySymbols[($0.offset + 1) % 7], seconds: $0.element)
            }, color: KeepTheme.sageInk)
        }
    }
    private func hourChart(_ snapshot: StatsSnapshot) -> some View {
        card {
            StatsBarChart(title: "Focus by hour", points: snapshot.hours.enumerated().map { .init(id: $0.offset, label: String(format: "%02d:00", $0.offset), seconds: $0.element) })
        }
    }
    private func distribution(_ snapshot: StatsSnapshot, compact: Bool = false) -> some View {
        StatsDistributionChart(rows: snapshot.distribution, showsTasks: model.query.projectID != nil, onSelect: { row in
            if let key = row.taskKey { model.query.taskKeys = [key] }
            else { model.query.projectID = row.projectID; model.query.taskKeys = nil }
        }, compact: compact)
    }

    private func goal(_ snapshot: StatsSnapshot) -> some View {
        VStack(spacing: 20) {
        card {
            HStack {
                Text("A weekly goal").font(KeepTheme.headingFont(size: 23))
                Spacer()
                Button(preferences.weeklyFocusGoalMinutes == nil ? "Set goal" : "Edit goal") { showsGoal = true }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(!preferences.canEdit)
            }
            Text("This week · all projects · Monday to Sunday").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            if let minutes = preferences.weeklyFocusGoalMinutes {
                Text("\(TimesheetDuration.total(snapshot.weeklyGoalSeconds)) of \(TimesheetDuration.total(Double(minutes * 60)))")
                    .font(KeepTheme.headingFont(size: 24)).monospacedDigit()
                ProgressView(value: min(1, snapshot.weeklyGoalSeconds / Double(minutes * 60)))
                    .accessibilityLabel("Weekly focus goal")
            } else { Text("Choose an amount of focus time that works for you.").font(.system(size: 14)).foregroundStyle(KeepTheme.secondaryInk) }
        }
        card {
            Text("Project targets").font(KeepTheme.headingFont(size: 23))
            Text("This week · recorded focus · all tasks · Monday to Sunday").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            ForEach(workspace.projects.filter { model.query.projectID == nil || $0.id == model.query.projectID }) { project in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(project.name, systemImage: "folder.fill").foregroundStyle(project.labelColor(in: environment))
                        Spacer()
                        Button(workspace.projectTargets[project.id] == nil ? "Set goals" : "Edit goals") { goalProject = project }
                            .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(!workspace.canTrack)
                            .accessibilityLabel("Weekly targets for \(project.name)")
                    }
                    if let targets = workspace.projectTargets[project.id] {
                        WeeklyTargetsProgress(targets: targets, amount: workspace.weeklyProjectSeconds(projectID: project.id) / 60) { TimesheetDuration.total($0 * 60) }
                    }
                }.padding(.vertical, 6)
            }
        }
        }
    }
    private func habitsContent(_ snapshot: StatsSnapshot) -> some View {
        card {
            Text("Habit consistency").font(KeepTheme.headingFont(size: 23))
            Text("All habits · selected dates").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            if let error = habits.persistenceError { issue(error) { habits.retryPersistence(); refresh() } }
            if !habits.loadFailed {
                if snapshot.habitsDue > 0 {
                    Text("\(rate(snapshot.habitsCompleted, snapshot.habitsDue)) · \(snapshot.habitsCompleted) of \(snapshot.habitsDue) check-ins")
                        .font(KeepTheme.headingFont(size: 24))
                } else { Text("No check-ins due").foregroundStyle(KeepTheme.mutedInk) }
                ForEach(snapshot.habits) { habit in
                    HStack(spacing: 12) {
                        Image(systemName: habit.icon).foregroundStyle((HabitIcon(rawValue: habit.icon) ?? .checkmark).ink(in: environment)).frame(width: 24)
                        Text(habit.name).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(habit.due == 0 ? "Not due" : "\(habit.completed)/\(habit.due) · \(rate(habit.completed, habit.due))")
                            .font(.system(size: 13)).monospacedDigit()
                    }.padding(.vertical, 6).accessibilityElement(children: .combine)
                    if let saved = habits.habits.first(where: { $0.id == habit.id }), let targets = saved.weeklyTargets {
                        WeeklyTargetsProgress(targets: targets, amount: Double(habits.weeklyAmount(for: saved))) { amount in
                            saved.weeklyUnit == "minutes" ? TimesheetDuration.total(amount * 60) : "\(Int(amount)) \(saved.weeklyUnit)"
                        }.padding(.bottom, 12)
                    }
                }
            }
        }
    }
    private func tasksContent(_ snapshot: StatsSnapshot) -> some View {
        card {
            Text("Small things, done").font(KeepTheme.headingFont(size: 23))
            Text("All tasks · assigned to selected dates").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            if let error = tasks.persistenceError { issue(error) { tasks.retryPersistence(); refresh() } }
            if !tasks.loadFailed {
                Text(snapshot.tasksTotal == 0 ? "No saved tasks for these dates" : "\(snapshot.tasksCompleted) of \(snapshot.tasksTotal) complete · \(rate(snapshot.tasksCompleted, snapshot.tasksTotal))")
                    .font(KeepTheme.headingFont(size: 24))
                Text("Based on current saved task lists, without completion timestamps or deleted tasks. Habit check-ins are counted separately.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            }
        }
    }
    private func streaks(_ snapshot: StatsSnapshot) -> some View {
        card {
            Text("A little consistency").font(KeepTheme.headingFont(size: 23))
            Text("Streak at range end / best within range. A streak can begin before the selected dates.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            if workspace.canTrack { streakRow("Focus · selected filters", current: snapshot.currentStreak, best: snapshot.bestStreak) }
            if !habits.loadFailed {
                ForEach(snapshot.habits) { streakRow($0.name, current: $0.currentStreak, best: $0.bestStreak, unit: "check-ins") }
            }
        }
    }
    private func streakRow(_ name: String, current: Int, best: Int, unit: String = "days") -> some View {
        HStack { Text(name).fixedSize(horizontal: false, vertical: true); Spacer(); Text("\(current) / \(best) \(unit)").monospacedDigit() }
            .font(.system(size: 14)).padding(.vertical, 4).accessibilityElement(children: .combine)
            .accessibilityLabel("\(name), streak at range end: \(current) \(unit), best within range: \(best) \(unit)")
    }
    private func rate(_ done: Int, _ total: Int) -> String { "\(Int((Double(done) / Double(max(1, total)) * 100).rounded()))%" }
    private func metric(_ title: String, value: String, detail: String, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(value).font(KeepTheme.headingFont(size: 29)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 12))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(20)
            .background(fill, in: RoundedRectangle(cornerRadius: 20)).accessibilityElement(children: .combine)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func issue(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry).buttonStyle(KeepButtonStyle(emphasis: .quiet))
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Stats") {
    AppShellView(initialTab: .stats, workspace: StatsPreviewData.workspace(), habits: StatsPreviewData.habits())
        .frame(width: 1000, height: 900)
}
