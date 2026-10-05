import AppKit

/// Flush the last partial interval on quit, even when every window has been closed.
final class WorkspaceApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: WorkspaceModel?

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.shutdown()
    }
}
