import SwiftUI

@main
struct keepApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceApplicationDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel(persistence: TimesheetPersistence())
    @State private var music = MusicPlayerModel()
    var body: some Scene {
        WindowGroup("Keep") {
            AppShellView(workspace: workspace, music: music)
                .onAppear {
                    appDelegate.workspace = workspace
                    appDelegate.music = music
                }
        }
        .defaultSize(width: 1000, height: 900)
    }
}
