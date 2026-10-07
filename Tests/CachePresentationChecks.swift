import AppKit
import SwiftUI

/// Native offscreen views with isolated data and silent Music fakes. Never touches live archives.
@main enum CachePresentationChecks {
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-cache-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let workspace = StatsPreviewData.workspace(), habits = StatsPreviewData.habits(), tasks = DailyTaskStore()
        let preferences = AppPreferences(); preferences.musicProvider = .appleMusic
        let music = MusicPlayerModel(catalog: AudiusClient(), playback: SilentPlayback(), preferences: preferences,
                                     appleMusic: SilentLibrary(), launchAppleMusic: {}, isMusicRunning: { true })
        let wallpapers = WallpaperLibrary()
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(AppShellView(initialTab: .dashboard, workspace: workspace, music: music, tasks: tasks, habits: habits, preferences: preferences, wallpapers: wallpapers), size: size, url: output.appendingPathComponent("timesheet-\(name)-\(appearance.rawValue).png"))
                try await render(DashboardView(workspace: workspace, initialPage: .calendar).frame(width: size.width - 48, height: size.height - 48).padding(24).background(KeepTheme.paper).keepAppearance(appearance), size: size, url: output.appendingPathComponent("calendar-\(name)-\(appearance.rawValue).png"))
            }
            for (name, viewport) in [("default", CGSize(width: 1000, height: 900)), ("narrow", CGSize(width: 680, height: 650))] {
                let size = NSSize(width: min(620, viewport.width - 48), height: min(720, viewport.height - 64))
                try await render(AppleMusicLibraryView(player: music, preferences: preferences, wallpapers: wallpapers).environment(\.musicLibraryViewport, viewport), size: size, url: output.appendingPathComponent("music-\(name)-\(appearance.rawValue).png"))
            }
        }
        await music.shutdown()?.value
        wallpapers.shutdown(); workspace.shutdown()
        print("Rendered 16 native cached Dashboard/Music layouts in \(output.path)")
    }
    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root); window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
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
