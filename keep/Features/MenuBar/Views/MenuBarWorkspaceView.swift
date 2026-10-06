import AppKit
import SwiftUI

struct MenuBarWorkspaceView: View {
    let workspace: WorkspaceModel
    @Bindable var music: MusicPlayerModel
    let tasks: DailyTaskStore
    let preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.controls
    @State private var editor = FocusTaskEditor()

    private enum Page { case controls, target }

    var body: some View {
        // MenuBarExtra measures its content before opening. A flexible-height
        // scroll fallback can report zero height and collapse the native panel.
        HStack(spacing: 0) {
            KeepScrollView { panelContent }
                .frame(width: 380, height: 600)
                .disabled(page != .controls)
                .accessibilityHidden(page != .controls)
            MenuBarTargetPicker(editor: editor, workspace: workspace, isVisible: page == .target,
                                onBack: cancelSelection, onSubmit: submitName,
                                onSelectProject: selectProject, onSelectTask: selectTask)
                .frame(width: 380, height: 600)
                .disabled(page != .target)
                .accessibilityHidden(page != .target)
        }
            .offset(x: page == .target ? -380 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: page)
            .frame(width: 380, height: 600, alignment: .leading)
            .clipped()
            .background(KeepTheme.paper)
            .foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
            .keepAppearance(preferences.appearance)
            .onDisappear { editor.cancel(); page = .controls }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Keep", systemImage: "leaf.fill").font(KeepTheme.headingFont(size: 23))
                Spacer()
                Button("Open Keep") { showWorkspace() }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
            }
            Button {
                editor.begin(in: workspace)
                page = .target
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workspace.selectedProject?.name ?? "No project")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(KeepTheme.mutedInk)
                        Text(workspace.taskName.isEmpty ? "Your next good idea" : workspace.taskName)
                            .font(.system(size: 14, weight: .medium)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            .accessibilityLabel("Choose project or task")
            .accessibilityValue(workspace.taskName.isEmpty ? "Your next good idea" : workspace.taskName)
            .disabled(!workspace.canTrack)

            timerControls
            rule
            todayTasks
            rule
            musicControls
            rule
            Button("Quit Keep") { NSApplication.shared.terminate(nil) }
                .buttonStyle(KeepButtonStyle(emphasis: .quiet))
        }
        .padding(20)
    }

    private var timerControls: some View {
        TimelineView(.animation(minimumInterval: 1,
                                paused: workspace.pomodoro.phase() != .running && workspace.flow.phase() != .running)) { _ in
            let instant = ContinuousClock.now
            let bothRunning = workspace.pomodoro.interval == .focus
                && workspace.pomodoro.phase(at: instant) == .running && workspace.flow.phase(at: instant) == .running
            VStack(spacing: 10) {
                timerRow(workspace.pomodoro, at: instant)
                timerRow(workspace.flow, at: instant)
                HStack {
                    Button {
                        workspace.startBothTimers()
                    } label: {
                        Label(bothRunning ? "Both running" : workspace.pomodoro.interval == .rest ? "Start focus + flow" : "Start both", systemImage: bothRunning ? "checkmark" : "play.fill")
                    }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .disabled(!workspace.canTrack || bothRunning)
                    Spacer(minLength: 0)
                    if workspace.pomodoro.interval == .focus && workspace.pomodoro.phase(at: instant) == .completed {
                        Button("\(Int(workspace.pomodoro.upcomingBreakDuration(at: instant) / 60))m break") {
                            workspace.startBreak()
                        }
                        .buttonStyle(KeepButtonStyle(emphasis: .quiet)).disabled(!workspace.canTrack)
                    }
                }
                if let error = workspace.persistenceError {
                    errorMessage(error) { workspace.retryPersistence() }
                }
            }
        }
    }

    private func timerRow(_ timer: FocusTimer, at instant: ContinuousClock.Instant) -> some View {
        let running = timer.phase(at: instant) == .running
        let title = timer.mode == .flow ? "Flow" : timer.interval == .rest ? "Pomodoro break" : "Pomodoro"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(timer.display(at: instant)).font(.system(size: 24, weight: .light)).monospacedDigit()
                    .accessibilityLabel("\(title) \(timer.mode == .flow ? "elapsed" : "remaining")")
                    .accessibilityValue(timer.display(at: instant))
            }
            Spacer(minLength: 0)
            Button {
                if running { workspace.stop(timer.mode) } else { workspace.play(timer.mode) }
            } label: {
                Label(running ? "Stop" : timer.phase(at: instant) == .stopped ? "Continue" : "Play", systemImage: running ? "stop.fill" : "play.fill")
                    .frame(minWidth: 70)
            }
            .buttonStyle(KeepButtonStyle(emphasis: .secondary))
            .accessibilityLabel("\(running ? "Stop" : "Start or resume") \(title)")
            .help(running ? "Stop and keep the current time" : "Start or continue this timer")
            .disabled(!workspace.canTrack)
            Button { workspace.reset(timer.mode) } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 12)
            }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            .accessibilityLabel("Reset \(title)").help("Reset \(title)")
            .disabled(!workspace.canTrack || timer.phase(at: instant) == .idle)
        }
        .padding(10)
        .background(KeepTheme.defaultTimerSurface(mode: timer.mode, isBreak: timer.interval == .rest),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var todayTasks: some View {
        let day = TaskDay.id(for: workspace.today, calendar: tasks.calendar)
        let rows = tasks.tasks(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today’s tasks").font(KeepTheme.headingFont(size: 18))
                Spacer()
                Text("\(rows.filter { !$0.isComplete }.count) left").font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
            }
            if let error = tasks.persistenceError ?? tasks.habitPersistenceError {
                errorMessage(error) { tasks.retryPersistence() }
            }
            if rows.isEmpty && !tasks.loadFailed {
                Text("No tasks planned for today.").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            } else {
                KeepScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rows, id: \.listID) { task in
                            Toggle(isOn: completionBinding(for: task, on: day)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                        .strikethrough(task.isComplete)
                                    if task.habitID != nil { Text("Habit").font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk) }
                                }
                            }
                            .toggleStyle(KeepCheckboxStyle())
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                            .accessibilityLabel(task.habitID == nil ? task.title : "Habit: \(task.title)")
                            .disabled(!tasks.canComplete(task, on: day, today: workspace.today))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                }
                .frame(height: min(160, CGFloat(rows.count) * 44))
                .accessibilityLabel("Today’s tasks")
            }
        }
    }

    private var musicControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Music").font(KeepTheme.headingFont(size: 18))
                Spacer()
                Text(music.provider.title).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
            }
            if let track = music.track {
                Text(track.title).font(.system(size: 13, weight: .medium)).lineLimit(1).help(track.title)
                Text(track.artist).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk).lineLimit(1)
            } else {
                Text("Ready when you are.").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            }
            HStack(spacing: 8) {
                musicButton("Previous track", symbol: "backward.end.fill", enabled: music.canSkip) { music.previous() }
                musicButton(music.wantsPlayback ? "Pause music" : "Play music", symbol: music.wantsPlayback ? "pause.fill" : "play.fill") { music.togglePlayback() }
                musicButton("Next track", symbol: "forward.end.fill", enabled: music.canSkip) { music.next() }
                if music.state == .loading {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading music")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                musicButton(music.volume > 0 ? "Mute music" : "Unmute music", symbol: music.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill", enabled: preferences.canEdit) { music.toggleMute() }
                Slider(value: $music.volume, in: 0...1)
                    .frame(height: 36).disabled(!preferences.canEdit)
                    .accessibilityLabel("Music volume")
                    .accessibilityValue("\(Int(music.volume * 100)) percent")
            }
            if case .failed(let failure) = music.state {
                errorMessage(failure.message) { music.retry() }
            }
        }
    }

    private func musicButton(_ title: String, symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 16) }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            .disabled(!enabled).accessibilityLabel(title).help(title)
    }

    private func errorMessage(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry).buttonStyle(KeepButtonStyle(emphasis: .quiet))
        }
    }

    private var rule: some View { Divider().overlay(KeepTheme.border).allowsHitTesting(false) }

    private func completionBinding(for task: FocusTask, on day: String) -> Binding<Bool> {
        Binding(get: {
            tasks.tasks(on: day).first { $0.listID == task.listID }?.isComplete ?? false
        }, set: { complete in
            let today = Date.now
            guard day == TaskDay.id(for: today, calendar: tasks.calendar),
                  let current = tasks.tasks(on: day).first(where: { $0.listID == task.listID }),
                  tasks.canComplete(current, on: day, today: today) else { return }
            tasks.setComplete(complete, taskID: current.id, on: day, habitID: current.habitID, today: today)
        })
    }

    private func cancelSelection() {
        editor.cancel()
        page = .controls
    }

    private func submitName() {
        guard workspace.canTrack else { return }
        editor.commit(to: workspace)
        page = .controls
    }

    private func selectProject(_ project: FocusProject?) {
        guard workspace.canTrack else { return }
        workspace.selectProject(project)
        cancelSelection()
    }

    private func selectTask(_ task: TaskActivity) {
        guard workspace.canTrack else { return }
        workspace.selectTask(task)
        cancelSelection()
    }

    private func showWorkspace() {
        NSApplication.shared.activate()
        if let window = NSApplication.shared.windows.first(where: { $0.title == "Keep" && $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "workspace")
        }
    }
}
