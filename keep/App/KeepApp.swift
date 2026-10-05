import SwiftUI

@main
struct keepApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceApplicationDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel(persistence: TimesheetPersistence())
    var body: some Scene {
        WindowGroup("Keep") {
            AppShellView(workspace: workspace)
                .onAppear { appDelegate.workspace = workspace }
        }
        .defaultSize(width: 1000, height: 900)
    }
}
