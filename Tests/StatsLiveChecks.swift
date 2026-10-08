import AppKit
import SwiftUI

/// Native viewport checks deliberately retain NSHostingView's default sizing.
/// Pinned offscreen hosts hide content-to-viewport measurement feedback loops.
@main enum StatsLiveChecks {
    static func main() {
        let app = NSApplication.shared
        let delegate = StatsWindowChecks()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class StatsWindowChecks: NSObject, NSApplicationDelegate {
    private var checks = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { preconditionFailure("Native Stats viewport check failed: \(error)") }
            NSApp.stop(nil)
            // Wake the native event loop so the standalone runner can exit.
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
    private func expect(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }
    private func run() async throws {
        let workspace = StatsPreviewData.workspace(), habits = StatsPreviewData.habits()
        let tasks = DailyTaskStore(habits: habits), preferences = AppPreferences()
        defer { workspace.shutdown() }
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1000, height: 900),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Keep — isolated Stats viewport checks"
        let host = NSHostingView(rootView: StatsView(workspace: workspace, tasks: tasks,
            habits: habits, preferences: preferences, isVisible: true)
            .padding(24).background(KeepTheme.paper).keepAppearance(preferences.appearance))
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            host.rootView = StatsView(workspace: workspace, tasks: tasks, habits: habits,
                preferences: preferences, isVisible: true)
                .padding(24).background(KeepTheme.paper).keepAppearance(appearance)
            for size in [NSSize(width: 1000, height: 900), NSSize(width: 680, height: 650), NSSize(width: 1710, height: 1080)] {
                window.setContentSize(size)
                try await Task.sleep(for: .milliseconds(650))
                host.layoutSubtreeIfNeeded()
                expect(abs(host.bounds.width - size.width) < 1, "Content must not expand the native window")
                let scrolls = scrollViews(in: host)
                guard let vertical = scrolls.max(by: { $0.bounds.height < $1.bounds.height }) else {
                    preconditionFailure("Missing native Stats scroll viewport")
                }
                expect(vertical.bounds.width >= size.width - 50, "Stats must fill the available width")
                expect((vertical.documentView?.bounds.height ?? 0) > vertical.bounds.height,
                    "Prepared statistics must replace the loading indicator")
                let width = vertical.bounds.width
                try await Task.sleep(for: .milliseconds(350))
                host.layoutSubtreeIfNeeded()
                expect(abs(vertical.bounds.width - width) < 1, "Scrollbar layout must settle without width growth")
                expect((vertical.documentView?.bounds.width ?? 0) <= width + 20,
                    "Stats content must remain inside its viewport")
            }
        }
        print("Passed \(checks) native Stats viewport checks")
    }
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
