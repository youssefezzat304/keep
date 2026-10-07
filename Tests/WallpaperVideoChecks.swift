import AppKit
import AVFoundation
import SwiftUI

/// Simulate native visibility without showing windows or changing the user's desktop.
private final class VideoFixtureWindow: NSWindow {
    var visibleForChecks = true
    override var isVisible: Bool { visibleForChecks }
    override var isMiniaturized: Bool { false }
    override var occlusionState: NSWindow.OcclusionState { visibleForChecks ? .visible : [] }
}

/// Generates silent local media; never touches user folders, music, or live archives.
@main enum WallpaperVideoChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        preconditionFailure("Wallpaper operation did not finish")
    }
    static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keep-video-checks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appendingPathComponent("01-live.MP4")
        try await fixture(videoURL)
        let still = root.appendingPathComponent("02-still.png")
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.coderInvalidValue) }
        context.setFillColor(red: 0.4, green: 0.7, blue: 0.3, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let frame = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        try ArtworkWash.png(frame).write(to: still)
        try Data([0, 1]).write(to: root.appendingPathComponent("03-broken.mp4"))
        try Data([0, 1]).write(to: root.appendingPathComponent("ignore.txt"))
        try FileManager.default.copyItem(at: videoURL, to: root.appendingPathComponent(".hidden.mp4"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.mp4"), withDestinationURL: videoURL)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let files = try WallpaperLibrary.wallpaperFiles(in: root)
        expect(files.map(\.lastPathComponent) == ["01-live.MP4", "02-still.png", "03-broken.mp4"], "Scans images and uppercase MP4, skipping hidden files, symlinks, folders and unrelated types")
        let preferences = AppPreferences(); preferences.wallpaperOrder = .sequential; preferences.automaticallyRotate = false
        let library = WallpaperLibrary()
        library.chooseFolder(root, preferences: preferences)
        try await waitUntil { !library.isLoading }
        expect(library.error == nil && library.count == 3 && library.video?.url.resolvingSymlinksInPath() == videoURL.resolvingSymlinksInPath() && library.image != nil, "MP4 selection creates a poster and a video resource")
        expect(library.backdrop(for: .folder) != nil && library.palette(for: .folder) != nil, "Video poster feeds existing wash/palette pipeline")
        guard let video = library.video else { preconditionFailure("No video selected") }
        let playback = WallpaperVideoPlayback()
        playback.configure(video, active: true) { _ in preconditionFailure("Valid video failed") }
        expect(playback.player.isMuted && playback.player.volume == 0 && !playback.player.preventsDisplaySleepDuringVideoPlayback, "Video remains silent and does not prevent display sleep")
        try await waitUntil { (playback.looper?.loopCount ?? 0) >= 2 }
        expect(playback.looper?.status == .ready && playback.player.rate > 0, "Native looper plays repeatedly across at least two boundaries")
        let looper = playback.looper
        playback.configure(video, active: true) { _ in }
        expect(playback.looper === looper, "Ordinary view updates do not restart decorative playback")
        let otherWindow = WallpaperVideoPlayback()
        otherWindow.configure(video, active: true) { _ in }
        expect(otherWindow.player !== playback.player && otherWindow.video === video, "Windows share the resource but own independent player/layer pairs")
        playback.configure(video, active: false) { _ in }
        expect(playback.player.rate == 0 && playback.player.items().isEmpty && playback.video == nil && playback.looper == nil, "Hidden renderers release their queue and looper")
        otherWindow.stop()
        try await nativePresentation(preferences: preferences, library: library)
        library.previous(); try await waitUntil { !library.isLoading }
        expect(library.video == nil && library.image != nil, "Previous skips corrupt files in the backward direction")
        library.previous(); try await waitUntil { !library.isLoading }
        expect(library.video != nil, "Previous reaches the preceding valid video")
        let output = URL(fileURLWithPath: "/tmp/keep-video-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(MusicPlayerCard(player: MusicPlayerModel(), preferences: preferences, wallpapers: library)
                    .padding(24).background(KeepTheme.paper).keepAppearance(appearance), size: size,
                                 url: output.appendingPathComponent("video-\(name)-\(appearance.rawValue).png"))
            }
        }
        library.next(); try await waitUntil { !library.isLoading }
        expect(library.video == nil && library.image != nil, "Moving to a still releases video selection")
        library.videoFailed(video)
        expect(library.error == nil, "A stale playback failure cannot overwrite the next wallpaper")
        library.next(); try await waitUntil { !library.isLoading }
        expect(library.video?.url.resolvingSymlinksInPath() == videoURL.resolvingSymlinksInPath() && library.error == nil, "Corrupt MP4 is skipped in favor of the next readable wallpaper")
        library.next(); try await waitUntil { !library.isLoading }
        expect(library.video == nil, "Rotation resumes after the successfully selected fallback file")
        library.next()
        preferences.wallpaperSource = .cozy; library.configure(preferences.snapshot.wallpaperConfiguration, preferences: preferences)
        try await Task.sleep(for: .milliseconds(150))
        expect(library.video == nil && library.image == nil && library.error == nil, "Switching sources fences an in-flight video/poster load")
        preferences.wallpaperSource = .folder; library.configure(preferences.snapshot.wallpaperConfiguration, preferences: preferences)
        try await waitUntil { !library.isLoading }
        expect(library.video != nil, "Returning to the selected folder reloads video")
        library.shutdown(); try await Task.sleep(for: .milliseconds(50))
        expect(library.video == nil, "Shutdown releases selected video access")
        let broken = root.appendingPathComponent("broken-only", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data([0, 1]).write(to: broken.appendingPathComponent("bad.mp4"))
        let failed = WallpaperLibrary(); failed.chooseFolder(broken, preferences: AppPreferences())
        try await waitUntil { !failed.isLoading }
        expect(failed.video == nil && failed.image == nil && failed.error != nil, "Unreadable video-only folders show an actionable error and static fallback")
        failed.shutdown()
        print("Passed \(checks) wallpaper video checks; rendered six native layouts in \(output.path)")
    }

    static func nativePresentation(preferences: AppPreferences, library: WallpaperLibrary) async throws {
        let window = VideoFixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = MusicArtworkView(preferences: preferences, wallpapers: library)
        let host = NSHostingView(rootView: root)
        window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: 160, height: 120)
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try await Task.sleep(for: .milliseconds(100))
            expect(nativePlayer(in: host) == nil, "Native Reduce Motion uses the poster without video")
            return
        }
        try await waitUntil { (nativePlayer(in: host)?.rate ?? 0) > 0 }
        guard let player = nativePlayer(in: host) else { preconditionFailure("Missing native video layer") }
        expect(player.isMuted && player.items().count > 0, "Actual artwork view attaches a silent native video renderer")
        window.visibleForChecks = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        try await waitUntil { player.items().isEmpty }
        expect(player.rate == 0, "Native occlusion releases video playback")
        window.visibleForChecks = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        try await waitUntil { player.rate > 0 }
        expect(player.items().count > 0, "Visible window resumes decorative playback")
        host.rootView = MusicArtworkView(preferences: preferences, wallpapers: library, animates: false)
        try await waitUntil { nativePlayer(in: host) == nil }
        expect(player.items().isEmpty, "Disabling animation removes native playback and retains the prepared poster")
    }

    static func nativePlayer(in view: NSView) -> AVQueuePlayer? {
        if let layer = view.layer?.sublayers?.compactMap({ $0 as? AVPlayerLayer }).first { return layer.player as? AVQueuePlayer }
        for child in view.subviews { if let player = nativePlayer(in: child) { return player } }
        return nil
    }

    nonisolated static func fixture(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<12 {
            for _ in 0..<500 {
                if input.isReadyForMoreMediaData { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            var pixel: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess,
                  let pixel else { throw CocoaError(.coderInvalidValue) }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let base = CVPixelBufferGetBaseAddress(pixel) {
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                for y in 0..<64 {
                    for x in 0..<64 {
                        let offset = y * CVPixelBufferGetBytesPerRow(pixel) + x * 4
                        bytes[offset] = 255; bytes[offset + 1] = UInt8(160 + index * 5)
                        bytes[offset + 2] = UInt8(90 + x * 2); bytes[offset + 3] = UInt8(60 + y)
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    static func render<V: View>(_ root: V, size: NSSize, url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: root); window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size); try await Task.sleep(for: .milliseconds(300)); view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close()
    }
}
