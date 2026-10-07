import AppKit
import SwiftUI

@main enum BackupPresentationChecks {
    static var count = 0
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: "/tmp/keep-backup-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "keep.backup.presentation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw BackupFailure.writeFailed }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let workspace = WorkspaceModel(), habits = HabitStore(), tasks = DailyTaskStore(habits: habits), preferences = AppPreferences()
        let music = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(), preferences: preferences, appleMusic: SilentMusic(), launchAppleMusic: {}, isMusicRunning: { false })
        let cloud = SilentCloud()
        let transaction = BackupRestoreTransaction(defaults: defaults, domain: suite, root: root)
        let backup = BackupModel(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, music: music, gate: BackupRestoreGate(), cloud: cloud, transaction: transaction, defaults: defaults)
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            for (name, size) in [("default", NSSize(width: 920, height: 350)), ("narrow", NSSize(width: 600, height: 390))] {
                try await render(BackupSettingsView(backup: backup).padding(16).background(KeepTheme.paper).keepAppearance(appearance), size: size, url: output.appendingPathComponent("disabled-\(name)-\(appearance.rawValue).png"))
            }
        }
        await backup.backUpNow()
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            try await render(BackupSettingsView(backup: backup).padding(16).background(KeepTheme.paper).keepAppearance(appearance), size: NSSize(width: 600, height: 390), url: output.appendingPathComponent("pending-narrow-\(appearance.rawValue).png"))
        }
        await backup.refreshVersions()
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            if let version = backup.versions.first { await backup.prepareRestore(version) }
            precondition(backup.preview != nil, "Restore layout must include its validated preview")
            try await render(BackupRestoreView(backup: backup).keepAppearance(appearance), size: NSSize(width: 540, height: 580), url: output.appendingPathComponent("restore-\(appearance.rawValue).png"))
        }
        cloud.isOffline = true; cloud.onChange?()
        try await Task.sleep(for: .milliseconds(100))
        try await render(BackupSettingsView(backup: backup).padding(16).background(KeepTheme.paper).keepAppearance(.dark), size: NSSize(width: 600, height: 390), url: output.appendingPathComponent("offline-dark.png"))
        backup.cancelPreview(); cloud.isOffline = false; cloud.account = nil; cloud.onChange?()
        try await Task.sleep(for: .milliseconds(100))
        try await render(BackupSettingsView(backup: backup).padding(16).background(KeepTheme.paper).keepAppearance(.light), size: NSSize(width: 600, height: 420), url: output.appendingPathComponent("account-changed-light.png"))
        workspace.shutdown(); await music.shutdown()?.value
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        print("Rendered \(count) native backup layouts in \(output.path)")
    }
    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root.frame(width: size.width, height: size.height, alignment: .topLeading)); view.sizingOptions = []; window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        precondition(view.bounds.size == size, "Native snapshot must use the requested viewport")
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw BackupFailure.writeFailed }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw BackupFailure.writeFailed }
        try png.write(to: url); window.close(); count += 1
        // Let SwiftUI finish onDisappear before the next fixture prepares its preview.
        try await Task.sleep(for: .milliseconds(100))
    }
}
private final class SilentPlayback: MusicPlayback {
    var volume: Float = 0.5
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {}
    func play() {}
    func pause() {}
    func stop() {}
}
private struct SilentCatalog: MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack] { throw MusicFailure.noTracks }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { throw MusicFailure.noTracks }
    func streamURL(for track: MusicTrack) async throws -> URL { throw MusicFailure.unavailable }
}
private actor SilentMusic: AppleMusicControlling {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot { .init(state: .stopped, title: nil, artist: nil) }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage { .init(items: [], hasMore: false) }
}
private final class SilentCloud: BackupCloudStorage {
    var account: Data? = Data("presentation-only".utf8)
    var versions: [BackupVersion] = []
    var isOffline = false
    var onChange: (() -> Void)?
    var data = Data()
    func connect() async throws { guard account != nil else { throw BackupFailure.unavailable } }
    func submit(_ data: Data, envelope: BackupEnvelope) async throws -> URL {
        self.data = data
        let url = URL(fileURLWithPath: "/fake/\(envelope.deviceID.uuidString)/\(envelope.filename)")
        versions = [BackupVersion(url: url, createdAt: envelope.createdAt, deviceID: envelope.deviceID.uuidString, downloaded: true)]
        return url
    }
    func read(_ version: BackupVersion) async throws -> Data { data }
    func remove(_ version: BackupVersion) async throws {}
}
