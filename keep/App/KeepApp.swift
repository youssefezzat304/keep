import SwiftUI

@main
struct keepApp: App {
    var body: some Scene {
        WindowGroup("Keep") {
            AppShellView()
        }
        .defaultSize(width: 1000, height: 900)
    }
}
