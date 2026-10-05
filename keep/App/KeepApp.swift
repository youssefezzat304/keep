import SwiftUI

@main
struct keepApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceApplicationDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel(persistence: TimesheetPersistence())
    @State private var music = MusicPlayerModel()
    @State private var tasks = DailyTaskStore(persistence: TaskPersistence())
    var body: some Scene {
        WindowGroup("Keep") {
            AppShellView(workspace: workspace, music: music, tasks: tasks)
                .onAppear {
                    appDelegate.workspace = workspace
                    appDelegate.music = music
                }
        }
        .defaultSize(width: 1000, height: 900)
    }
}
