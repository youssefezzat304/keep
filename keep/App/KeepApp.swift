import SwiftUI

@main
struct keepApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceApplicationDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel(persistence: TimesheetPersistence())
    @State private var music: MusicPlayerModel
    @State private var preferences: AppPreferences
    @State private var wallpapers = WallpaperLibrary()
    @State private var tasks = DailyTaskStore(persistence: TaskPersistence())
    @State private var habits = HabitStore(persistence: HabitPersistence())
    init() {
        let preferences = AppPreferences(persistence: SettingsPersistence())
        let music = MusicPlayerModel(preferences: preferences)
        music.selectChannel(preferences.selectedChannel)
        _preferences = State(initialValue: preferences)
        _music = State(initialValue: music)
    }

    var body: some Scene {
        WindowGroup("Keep") {
            AppShellView(workspace: workspace, music: music, tasks: tasks, habits: habits, preferences: preferences, wallpapers: wallpapers)
                .onAppear {
                    appDelegate.workspace = workspace
                    appDelegate.music = music
                    appDelegate.wallpapers = wallpapers
                }
        }
        .defaultSize(width: 1000, height: 900)
    }
}
