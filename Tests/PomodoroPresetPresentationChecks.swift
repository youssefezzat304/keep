import AppKit
import SwiftUI

/// Native popover fixtures with isolated workspace state; no live archives or playback.
/// KEEP_PRESETS_INTERACTIVE=1 opens a disposable fixture for keyboard/accessibility review.
@main enum PomodoroPresetPresentationChecks {
    static var renders = 0

    static func main() {
        let app = NSApplication.shared
        let runner = PresetPresentationRunner()
        app.delegate = runner
        app.run()
        withExtendedLifetime(runner) {}
    }

    static func run() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-preset-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        defer { workspace.shutdown() }
        try workspace.savePomodoroPreset(name: "Writing", settings: .init(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20, iterationsBeforeLongBreak: 4))
        try workspace.savePomodoroPreset(name: "Reading and reflection with a longer preset name that should wrap", settings: .defaults)
        try workspace.savePomodoroPreset(name: "Quick task", settings: .init(focusMinutes: 15))
        try workspace.savePomodoroPreset(name: "Study", settings: .init(focusMinutes: 40))

        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                let host = NSHostingView(rootView: PresetFixture(workspace: workspace).padding(24)
                    .frame(width: size.width, height: size.height).background(KeepTheme.surface).keepAppearance(appearance))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                try await Task.sleep(for: .milliseconds(250))
                try snapshot(host, to: output.appendingPathComponent("settings-\(label)-\(appearance.rawValue).png"))
                precondition(host.bounds.size == size, "The popover must fit its viewport")
                window.close()
            }
        }
        print("Rendered \(renders) native settings layouts in light/dark at default/narrow sizes. Output: \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_PRESETS_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Keep — isolated preset fixture"
            window.contentView = NSHostingView(rootView: InteractivePresetFixture(workspace: workspace, window: window))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(100))
            window.close()
        }
    }

    static func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try data.write(to: url)
        renders += 1
    }
}

private final class PresetPresentationRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await PomodoroPresetPresentationChecks.run() }
            catch { preconditionFailure("Preset presentation failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}

private struct PresetFixture: View {
    let workspace: WorkspaceModel
    var body: some View {
        PomodoroSettingsPopover(settings: workspace.pomodoroSettings, presets: workspace.pomodoroPresets,
            onSavePreset: { try workspace.savePomodoroPreset(name: $0, settings: $1) },
            onRemovePreset: { try workspace.removePomodoroPreset(id: $0) }) { workspace.updatePomodoroSettings($0) }
    }
}

private struct InteractivePresetFixture: View {
    let workspace: WorkspaceModel
    let window: NSWindow
    @State private var appearance: AppAppearance = .light
    var body: some View {
        VStack {
            HStack {
                Button("Light") { appearance = .light }
                Button("Dark") { appearance = .dark }
                Button("Default size") { window.setContentSize(NSSize(width: 1000, height: 900)) }
                Button("Narrow size") { window.setContentSize(NSSize(width: 680, height: 650)) }
            }
            Text("Applied: \(workspace.pomodoroSettings.focusMinutes) minutes")
            Spacer()
            PresetFixture(workspace: workspace)
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeepTheme.surface).keepAppearance(appearance)
    }
}
