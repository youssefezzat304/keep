import SwiftUI

@main
struct keepApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceApplicationDelegate.self) private var appDelegate
    @State private var workspace: WorkspaceModel
    @State private var updater: AppUpdater
    @State private var music: MusicPlayerModel
    @State private var preferences: AppPreferences
    @State private var wallpapers: WallpaperLibrary
    @State private var tasks: DailyTaskStore
    @State private var habits: HabitStore
    @State private var backup: BackupModel
    @State private var loginItem = LoginItemModel()
    init() {
        let gate = BackupRestoreGate()
        let transaction = BackupRestoreTransaction()
        do { try transaction.recoverBeforeLoading() }
        catch {
            gate.isLocked = true
            gate.recoveryError = "Keep couldn’t recover an interrupted restore. Saved data is protected. Restart after checking disk access and space. " + error.localizedDescription
        }
        var workspacePersistence = TimesheetPersistence(); workspacePersistence.access = gate
        var taskPersistence = TaskPersistence(); taskPersistence.access = gate
        var habitPersistence = HabitPersistence(); habitPersistence.access = gate
        var settingsPersistence = SettingsPersistence(); settingsPersistence.access = gate
        let workspace = WorkspaceModel(persistence: workspacePersistence)
        _workspace = State(initialValue: workspace)
        let habits = HabitStore(persistence: habitPersistence)
        _habits = State(initialValue: habits)
        let tasks = DailyTaskStore(persistence: taskPersistence, habits: habits)
        _tasks = State(initialValue: tasks)
        let preferences = AppPreferences(persistence: settingsPersistence)
        let music = MusicPlayerModel(preferences: preferences, systemControls: MusicSystemController())
        let wallpapers = WallpaperLibrary()
        music.onTrackChange = { [weak wallpapers] provider, id in wallpapers?.songChanged(provider: provider, trackID: id) }
        _wallpapers = State(initialValue: wallpapers)
        music.selectChannel(preferences.selectedChannel)
        _preferences = State(initialValue: preferences)
        _music = State(initialValue: music)
        _backup = State(initialValue: BackupModel(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, music: music, gate: gate, transaction: transaction))
        _updater = State(initialValue: AppUpdater(workspace: workspace, preferences: preferences))
    }

    var body: some Scene {
        WindowGroup("Keep", id: "workspace") {
            AppShellView(workspace: workspace, music: music, tasks: tasks, habits: habits, preferences: preferences, wallpapers: wallpapers, loginItem: loginItem, updater: updater, backup: backup)
                .id(backup.gate.generation)
                .disabled(backup.gate.isLocked)
                .overlay {
                    if let error = backup.gate.recoveryError {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Saved data is protected").font(KeepTheme.headingFont(size: 24))
                            Text(error).fixedSize(horizontal: false, vertical: true)
                            Button("Quit Keep") { NSApplication.shared.terminate(nil) }
                        }
                        .padding(24).frame(maxWidth: 480).foregroundStyle(KeepTheme.ink)
                        .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                        .keepAppearance(preferences.appearance)
                    }
                }
                .onAppear {
                    connectRuntime()
                }
        }
        .defaultSize(width: 1000, height: 900)
        .commands {
            MusicCommands(player: music, preferences: preferences)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isStarted || !updater.canCheckForUpdates)
            }
        }

        MenuBarExtra(isInserted: Binding(get: { preferences.menuBarEnabled }, set: { preferences.menuBarEnabled = $0 })) {
            MenuBarWorkspaceView(workspace: workspace, music: music, tasks: tasks, preferences: preferences, wallpapers: wallpapers)
                .id(backup.gate.generation)
                .disabled(backup.gate.isLocked)
                .onAppear { connectRuntime() }
        } label: {
            MenuBarLabel(workspace: workspace, timer: preferences.menuBarTimer, showFlowSeconds: preferences.menuBarShowSeconds)
                .onAppear { connectRuntime() }
        }
        .menuBarExtraStyle(.window)
    }

    private func connectRuntime() {
        appDelegate.backup = backup
        appDelegate.workspace = workspace
        appDelegate.music = music
        appDelegate.wallpapers = wallpapers
        workspace.startUpdating()
        if !backup.gate.isLocked { updater.start() }
        backup.start()
    }
}
