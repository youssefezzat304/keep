import AppKit

/// Flush the last partial interval on quit, even when every window has been closed.
final class WorkspaceApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel?
    weak var wallpapers: WallpaperLibrary?
    weak var music: MusicPlayerModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let release = music?.shutdown() else { return .terminateNow }
        Task {
            await release.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.shutdown()
        music?.shutdown()
        wallpapers?.shutdown()
    }
}
