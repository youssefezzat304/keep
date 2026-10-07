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
    @State private var loginItem = LoginItemModel()
    init() {
        let workspace = WorkspaceModel(persistence: TimesheetPersistence())
        _workspace = State(initialValue: workspace)
        let habits = HabitStore(persistence: HabitPersistence())
        _habits = State(initialValue: habits)
        _tasks = State(initialValue: DailyTaskStore(persistence: TaskPersistence(), habits: habits))
        let preferences = AppPreferences(persistence: SettingsPersistence())
        let music = MusicPlayerModel(preferences: preferences, systemControls: MusicSystemController())
        let wallpapers = WallpaperLibrary()
        music.onTrackChange = { [weak wallpapers] provider, id in wallpapers?.songChanged(provider: provider, trackID: id) }
        _wallpapers = State(initialValue: wallpapers)
        music.selectChannel(preferences.selectedChannel)
        _preferences = State(initialValue: preferences)
        _music = State(initialValue: music)
        _updater = State(initialValue: AppUpdater(workspace: workspace, preferences: preferences))
    }

    var body: some Scene {
        WindowGroup("Keep", id: "workspace") {
            AppShellView(workspace: workspace, music: music, tasks: tasks, habits: habits, preferences: preferences, wallpapers: wallpapers, loginItem: loginItem, updater: updater)
                .onAppear {
                    connectRuntime()
                }
        }
        .defaultSize(width: 1000, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isStarted || !updater.canCheckForUpdates)
            }
        }

        MenuBarExtra(isInserted: Binding(get: { preferences.menuBarEnabled }, set: { preferences.menuBarEnabled = $0 })) {
            MenuBarWorkspaceView(workspace: workspace, music: music, tasks: tasks, preferences: preferences)
                .onAppear { connectRuntime() }
        } label: {
            MenuBarLabel(workspace: workspace, timer: preferences.menuBarTimer)
                .onAppear { connectRuntime() }
        }
        .menuBarExtraStyle(.window)
    }

    private func connectRuntime() {
        appDelegate.workspace = workspace
        appDelegate.music = music
        appDelegate.wallpapers = wallpapers
        workspace.startUpdating()
        updater.start()
    }
}
