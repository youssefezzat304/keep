import SwiftUI

@main
struct keepApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceApplicationDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel(persistence: TimesheetPersistence())
    @State private var music: MusicPlayerModel
    @State private var preferences: AppPreferences
    @State private var wallpapers = WallpaperLibrary()
    @State private var tasks: DailyTaskStore
    @State private var habits: HabitStore
    init() {
        let habits = HabitStore(persistence: HabitPersistence())
        _habits = State(initialValue: habits)
        _tasks = State(initialValue: DailyTaskStore(persistence: TaskPersistence(), habits: habits))
        let preferences = AppPreferences(persistence: SettingsPersistence())
        let music = MusicPlayerModel(preferences: preferences)
        music.selectChannel(preferences.selectedChannel)
        _preferences = State(initialValue: preferences)
        _music = State(initialValue: music)
    }

    var body: some Scene {
        WindowGroup("Keep", id: "workspace") {
            AppShellView(workspace: workspace, music: music, tasks: tasks, habits: habits, preferences: preferences, wallpapers: wallpapers)
                .onAppear {
                    connectRuntime()
                }
        }
        .defaultSize(width: 1000, height: 900)

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
    }
}
