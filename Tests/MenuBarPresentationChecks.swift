import AppKit
import SwiftUI

/// Actual native status item and disposable menu controls, with no live archives.
/// KEEP_MENU_INTERACTIVE=1 keeps the fixture open briefly for native input review.
@main struct MenuBarPresentationChecks: App {
    @NSApplicationDelegateAdaptor(MenuPresentationDelegate.self) private var appDelegate
    @State private var workspace = WorkspaceModel(focusDuration: 120, breakDuration: 60)
    @State private var preferences = AppPreferences()
    @State private var tasks = DailyTaskStore()
    @State private var wallpapers = WallpaperLibrary()
    @State private var music = MusicPlayerModel()

    var body: some Scene {
        WindowGroup("Keep — isolated menu bar fixture") {
            VStack(spacing: 12) {
                HStack {
                    Button("Prefer Flow") { preferences.menuBarTimer = .flow }
                    Button("Prefer Pomodoro") { preferences.menuBarTimer = .pomodoro }
                    Button("Icon only") { preferences.menuBarTimer = .none }
                }
                HStack {
                    Button("Light") { preferences.appearance = .light }
                    Button("Dark") { preferences.appearance = .dark }
                    Toggle("Pomodoro", isOn: $preferences.showPomodoroTimer)
                    Toggle("Flow", isOn: $preferences.showFlowTimer)
                }
                MenuBarWorkspaceView(workspace: workspace, music: music, tasks: tasks,
                    preferences: preferences, wallpapers: wallpapers)
            }.padding(20).background(KeepTheme.paper).keepAppearance(preferences.appearance)
                .task {
                    preferences.menuBarTimer = .flow
                    let instant = ContinuousClock.now
                    workspace.play(.pomodoro, at: instant.advanced(by: .seconds(-60)), date: Date.now.addingTimeInterval(-60))
                    workspace.synchronize(at: instant)
                    workspace.startUpdating()
                }
                .onDisappear { workspace.shutdown() }
        }.defaultSize(width: 500, height: 800)
        MenuBarExtra {
            MenuBarWorkspaceView(workspace: workspace, music: music, tasks: tasks,
                preferences: preferences, wallpapers: wallpapers)
        } label: {
            MenuBarLabel(workspace: workspace, timer: preferences.menuBarTimer,
                showFlowSeconds: preferences.menuBarShowSeconds,
                showPomodoroProgress: preferences.showPomodoroProgress,
                showPomodoroTimer: preferences.showPomodoroTimer, showFlowTimer: preferences.showFlowTimer)
        }.menuBarExtraStyle(.window)
    }

    static func renderFixtures() async throws {
        let output = URL(fileURLWithPath: "/tmp/keep-menu-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var renders = 0
        for appearance in [AppAppearance.light, .dark] {
            for state in ["idle", "half", "completed", "break", "both", "flow", "hide-pomodoro", "hide-flow", "hide-both"] {
                let model = fixture(state)
                let settings = AppPreferences()
                settings.appearance = appearance
                settings.showPomodoroTimer = !["hide-pomodoro", "hide-both"].contains(state)
                settings.showFlowTimer = !["hide-flow", "hide-both"].contains(state)
                let root = MenuBarWorkspaceView(workspace: model, music: MusicPlayerModel(), tasks: DailyTaskStore(),
                    preferences: settings, wallpapers: WallpaperLibrary())
                let host = NSHostingView(rootView: root)
                let size = NSSize(width: 380, height: 680)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                    backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                precondition(host.bounds.size == size, "The progress outline must not change native panel sizing")
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
                try png.write(to: output.appendingPathComponent("\(state)-\(appearance.rawValue).png"))
                window.close()
                model.shutdown()
                renders += 1
            }
        }
        for (name, text, progress) in [("idle", "25:00", 0.0), ("quarter", "18:45", 0.25),
            ("half", "12:30", 0.5), ("completed", "00:00", 1.0)] {
            guard let image = MenuBarLabel.renderImage(text: text, progress: progress),
                  let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
            precondition(image.isTemplate && image.size.height <= 22, "Status images fit the native menu bar and follow its appearance")
            try png.write(to: output.appendingPathComponent("label-\(name).png"))
            renders += 1
        }
        FileHandle.standardOutput.write(Data("Rendered \(renders) native panel/status images in \(output.path)\n".utf8))
    }

    private static func fixture(_ state: String) -> WorkspaceModel {
        let model = WorkspaceModel(focusDuration: 120, breakDuration: 60)
        let instant = ContinuousClock.now
        let date = Date.now
        if ["half", "both", "hide-pomodoro", "hide-flow", "hide-both"].contains(state) {
            model.play(.pomodoro, at: instant.advanced(by: .seconds(-60)), date: date.addingTimeInterval(-60))
            if state == "half" { model.stop(.pomodoro, at: instant, date: date) }
        }
        if ["completed", "break"].contains(state) {
            let start = instant.advanced(by: .seconds(state == "break" ? -150 : -120))
            model.play(.pomodoro, at: start, date: date.addingTimeInterval(state == "break" ? -150 : -120))
            if state == "break" {
                model.startBreak(at: instant.advanced(by: .seconds(-30)), date: date.addingTimeInterval(-30))
                model.stop(.pomodoro, at: instant, date: date)
            }
        }
        if ["flow", "both", "hide-pomodoro", "hide-flow", "hide-both"].contains(state) {
            model.play(.flow, at: instant.advanced(by: .seconds(-10)), date: date.addingTimeInterval(-10))
        }
        model.synchronize(at: instant, date: date)
        return model
    }
}

private final class MenuPresentationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run checks independently of whether a WindowGroup has mounted.
        Task {
            do {
                try await MenuBarPresentationChecks.renderFixtures()
                if ProcessInfo.processInfo.environment["KEEP_MENU_INTERACTIVE"] == "1" {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    FileHandle.standardOutput.write(Data("Interactive menu fixture ready.\n".utf8))
                    try await Task.sleep(for: .seconds(60))
                }
                // A status scene can defer ordinary termination; this disposable
                // process has no documents or archives to save.
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                preconditionFailure("Menu presentation failed: \(error)")
            }
        }
    }
}
