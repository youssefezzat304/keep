import AppKit
import SwiftUI

@main enum ExportPresentationChecks {
    static func main() {
        let app = NSApplication.shared
        let delegate = ExportWindows()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class ExportWindows: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { preconditionFailure("Export presentation failed: \(error)") }
            NSApp.terminate(nil)
        }
    }
    func run() async throws {
        let workspace = WorkspaceModel(), tasks = DailyTaskStore(), habits = HabitStore(), preferences = AppPreferences()
        let gate = BackupRestoreGate()
        let capture = SnapshotCapture(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, gate: gate)
        let model = ExportModel(capture: capture)
        let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 680, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Keep — isolated export checks"; window.isReleasedWhenClosed = false
        if ProcessInfo.processInfo.environment["KEEP_EXPORT_INTERACTIVE"] == "1" {
            let host = NSHostingView(rootView: KeepScrollView { ExportSettingsView(model: model).padding(24) }.background(KeepTheme.paper).keepAppearance(.light))
            window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            print("Interactive export fixture ready; native save uses only empty in-memory stores")
            try await Task.sleep(for: .seconds(90))
            window.close()
            return
        }
        let output = URL(fileURLWithPath: "/tmp/keep-export-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checks = 0
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                let host = NSHostingView(rootView: KeepScrollView { ExportSettingsView(model: model).padding(24) }.background(KeepTheme.paper).keepAppearance(appearance))
                window.contentView = host; window.setContentSize(size); window.makeKeyAndOrderFront(nil)
                for data in ExportData.allCases {
                    model.data = data
                    if data != .timesheet { model.projectID = "keep" }
                    try await Task.sleep(for: .milliseconds(250))
                    host.layoutSubtreeIfNeeded()
                    precondition(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1)
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
                    try png.write(to: output.appendingPathComponent("export-\(data.rawValue)-\(label)-\(appearance.rawValue).png"))
                    checks += 1
                }
            }
        }
        window.close()
        print("Export native layouts passed: \(checks); captures in \(output.path)")
    }
}
