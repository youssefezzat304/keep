import AVFoundation
import Foundation

/// Read-only access lives as long as any visible renderer retains this selected video.
/// The library owns selection; each visible presentation owns its native player/layer pair.
final class WallpaperVideo {
    let url: URL
    let asset: AVURLAsset
    private let folder: URL
    private let scoped: Bool

    init(url: URL, folder: URL) throws {
        guard url.isFileURL, url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else {
            throw CocoaError(.fileReadNoPermission)
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
        } catch {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            throw error
        }
        self.url = url; self.folder = folder; self.scoped = scoped
        asset = Self.makeAsset(for: url)
    }

    nonisolated static func makeAsset(for url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
    }

    deinit { if scoped { folder.stopAccessingSecurityScopedResource() } }
}

/// Decorative playback never changes Music, system volume, or the focus recorder.
final class WallpaperVideoPlayback {
    let player = AVQueuePlayer()
    private(set) var looper: AVPlayerLooper?
    private(set) var video: WallpaperVideo?
    private var observation: NSKeyValueObservation?
    private var onFailure: ((WallpaperVideo) -> Void)?

    init() { player.isMuted = true; player.volume = 0; player.preventsDisplaySleepDuringVideoPlayback = false }

    func configure(_ video: WallpaperVideo?, active: Bool, onFailure: @escaping (WallpaperVideo) -> Void) {
        guard active, let video else { stop(); return }
        guard self.video !== video else { return }
        stop()
        self.video = video; self.onFailure = onFailure
        let item = AVPlayerItem(asset: video.asset)
        item.preferredMaximumResolution = CGSize(width: 2048, height: 2048)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        self.looper = looper
        observation = looper.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.looper?.status == .failed, let current = self.video else { return }
                self.onFailure?(current)
                self.stop()
            }
        }
        player.play()
    }

    func stop() {
        observation = nil
        player.pause(); looper?.disableLooping(); looper = nil
        player.removeAllItems(); video = nil; onFailure = nil
    }
}
