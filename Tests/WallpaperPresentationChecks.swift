import AppKit
import SwiftUI

/// Native offscreen views with isolated data and silent Music fakes. Never touches live archives.
@main enum WallpaperPresentationChecks {
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-wallpaper-controls-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferences = AppPreferences(); preferences.wallpaperSource = .folder
        preferences.wallpaperIntervalChoice = .custom; preferences.customRotationMinutes = 750
        let music = MusicPlayerModel(catalog: AudiusClient(), playback: SilentPlayback(), preferences: preferences,
                                     appleMusic: SilentLibrary(), launchAppleMusic: {}, isMusicRunning: { false })
        let wallpapers = WallpaperLibrary()
        let workspace = WorkspaceModel()
        let project = try workspace.createProject(name: "German", accent: .sage)
        workspace.selectProject(project)
        workspace.startTask("hören", timers: .both)
        workspace.startTask("lesen", timers: .both)
        workspace.stopBothTimers()
        let editor = FocusTaskEditor(); editor.begin(in: workspace)
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(AppShellView(initialTab: .settings, music: music, preferences: preferences, wallpapers: wallpapers),
                                 size: size, url: output.appendingPathComponent("settings-shell-\(name)-\(appearance.rawValue).png"))
                try await render(settingsSection(preferences: preferences, music: music, wallpapers: wallpapers, anchor: .bottom)
                    .keepAppearance(appearance), size: size,
                                 url: output.appendingPathComponent("settings-full-\(name)-\(appearance.rawValue).png"))
            }
            try await render(KeepOptionList(label: "Wallpaper interval", options: WallpaperIntervalChoice.all, selection: .custom, title: { $0.title }, onSelect: { _ in })
                .keepAppearance(appearance), size: NSSize(width: 260, height: 296), url: output.appendingPathComponent("interval-list-\(appearance.rawValue).png"))
            try await render(HabitCreationDialog(store: HabitStore(), goal: .amount(target: 20, unit: .minutes)).keepAppearance(appearance),
                             size: NSSize(width: 460, height: 720), url: output.appendingPathComponent("habit-choices-\(appearance.rawValue).png"))
            try await render(AppleMusicLibraryView(player: music, preferences: preferences, wallpapers: wallpapers).keepAppearance(appearance),
                             size: NSSize(width: 620, height: 720), url: output.appendingPathComponent("music-choices-\(appearance.rawValue).png"))
            editor.text = "A completely new task"
            try await render(MenuBarTargetPicker(editor: editor, workspace: workspace, isVisible: false,
                onBack: {}, onSubmit: { editor.commit(to: workspace) }, onSelectProject: { _ in }, onSelectTask: { _ in })
                .background(KeepTheme.paper).keepAppearance(appearance), size: NSSize(width: 380, height: 680),
                url: output.appendingPathComponent("name-only-menu-\(appearance.rawValue).png"))
            try await render(MusicPlayerCard(player: music, preferences: preferences, wallpapers: wallpapers, onEnterZen: {})
                .keepAppearance(appearance), size: NSSize(width: 500, height: 400),
                url: output.appendingPathComponent("music-card-\(appearance.rawValue).png"))
            preferences.wallpaperRotationTrigger = .song
            try await render(settingsSection(preferences: preferences, music: music, wallpapers: wallpapers, anchor: .bottom)
                .keepAppearance(appearance), size: NSSize(width: 680, height: 900),
                             url: output.appendingPathComponent("song-settings-\(appearance.rawValue).png"))
            preferences.wallpaperRotationTrigger = .interval
        }
        workspace.shutdown()
        await music.shutdown()?.value
        wallpapers.shutdown()
        print("Rendered 24 native wallpaper/settings/choice layouts in \(output.path)")
    }
    static func settingsSection(preferences: AppPreferences, music: MusicPlayerModel, wallpapers: WallpaperLibrary, anchor: UnitPoint) -> some View {
        ScrollViewReader { scroll in
            KeepScrollView {
                SettingsView(preferences: preferences, player: music, wallpapers: wallpapers, isVisible: false)
                    .padding(24).id("settings")
            }
            .background(KeepTheme.paper)
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                scroll.scrollTo("settings", anchor: anchor)
            }
        }
    }
    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root.frame(width: size.width, height: size.height).clipped()); window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(350))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close()
    }
}
private final class SilentPlayback: MusicPlayback {
    var volume: Float = 0.5
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {}
    func play() {}
    func pause() {}
    func stop() {}
}
private actor SilentLibrary: AppleMusicControlling {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot { .init(state: .stopped, title: nil, artist: nil) }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage {
        .init(items: (0..<8).map { .init(nativeID: Int32($0), kind: .songs, title: $0 == 0 ? "A longer song name that should remain readable in the narrow library sheet" : "A little music \($0)", artist: "An artist") }, hasMore: false)
    }
}
