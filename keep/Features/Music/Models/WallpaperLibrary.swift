import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

struct WallpaperConfiguration: Equatable {
    let source: WallpaperSource
    let bookmark: Data?
    let order: WallpaperOrder
    let seconds: Int
    let automatic: Bool
    let loop: Bool
}

extension SettingsArchive {
    var wallpaperConfiguration: WallpaperConfiguration {
        WallpaperConfiguration(source: wallpaperSource, bookmark: folderBookmark, order: wallpaperOrder,
                               seconds: rotationSeconds, automatic: automaticallyRotate, loop: loopWallpapers)
    }
}

/// A shuffled cycle visits every image once, then starts a fresh cycle only when looping is enabled.
struct WallpaperCycle {
    private(set) var indices: [Int] = []
    private(set) var position = 0
    var current: Int? { indices.indices.contains(position) ? indices[position] : nil }
    mutating func reset(count: Int, shuffled: Bool) {
        indices = Array(0..<max(0, count))
        if shuffled { indices.shuffle() }
        position = 0
    }
    mutating func advance(loop: Bool, shuffled: Bool) -> Int? {
        guard !indices.isEmpty else { return nil }
        if position + 1 < indices.count { position += 1; return current }
        guard loop else { return nil }
        let last = current
        if shuffled {
            indices.shuffle()
            if indices.count > 1, indices.first == last { indices.swapAt(0, 1) }
        }
        position = 0
        return current
    }
}

@Observable
final class WallpaperLibrary {
    private struct DecodedArtwork: Sendable {
        let image: Data
        let wash: Data
        let palette: ArtworkPalette?
    }
    private(set) var image: NSImage?
    private var decodedBackdrop: NSImage?
    private var bundledBackdrop: NSImage?
    private var decodedPalette: ArtworkPalette?
    private var bundledPalette: ArtworkPalette?
    private(set) var count = 0
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var rotationFinished = false
    @ObservationIgnored private var configuration: WallpaperConfiguration?
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var files: [URL] = []
    @ObservationIgnored private var cycle = WallpaperCycle()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var rotationTask: Task<Void, Never>?
    @ObservationIgnored private var bundledBackdropTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var artworkURL: URL?
    @ObservationIgnored private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral)
        prepareBundledBackdrop()
    }

    var canAdvance: Bool { configuration?.source == .folder && count > 1 && !isLoading }

    func backdrop(for source: WallpaperSource) -> NSImage? {
        source == .cozy || image == nil ? bundledBackdrop : decodedBackdrop
    }

    func palette(for source: WallpaperSource) -> ArtworkPalette? {
        source == .cozy || image == nil ? bundledPalette : decodedPalette
    }

    private func prepareBundledBackdrop() {
        guard let image = NSImage(named: "CozyCorner")?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        bundledBackdropTask = Task { [weak self] in
            let operation = Task.detached {
                (try ArtworkWash.render(image), try ArtworkPaletteSampler.sample(image))
            }
            do {
                let data = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
                try Task.checkCancellation()
                self?.bundledBackdrop = NSImage(data: data.0)
                self?.bundledPalette = data.1
            } catch {
                // The semantic background remains available if the bundled image cannot be decoded.
            }
        }
    }

    func configure(_ newValue: WallpaperConfiguration, preferences: AppPreferences) {
        guard configuration != newValue else { return }
        let needsReload = configuration?.bookmark != newValue.bookmark || configuration?.source != newValue.source
        configuration = newValue
        rotationTask?.cancel()
        rotationFinished = false
        if newValue.source != .folder {
            loadTask?.cancel(); generation = UUID()
            image = nil; isLoading = false; error = nil
            if newValue.source == .audius { loadArtwork() }
            return
        }
        if needsReload || files.isEmpty { loadFolder(preferences: preferences) }
        else {
            cycle.reset(count: files.count, shuffled: newValue.order == .shuffle)
            if let index = cycle.current { showImage(at: index) }
        }
    }

    /// One decoded artwork image feeds both the player and the window, across tabs/windows.
    func setArtworkURL(_ url: URL?) {
        guard artworkURL != url else { return }
        artworkURL = url
        if configuration?.source == .audius { loadArtwork() }
    }

    private func loadArtwork() {
        loadTask?.cancel(); generation = UUID()
        let token = generation
        image = nil; isLoading = false
        guard let url = artworkURL, url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return }
        isLoading = true
        loadTask = Task { [weak self, session] in
            do {
                let request = URLRequest(url: url, timeoutInterval: 20)
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                      data.count <= 12 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                let operation = Task.detached { try Self.artworkThumbnail(data) }
                let thumbnail = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.image = NSImage(data: thumbnail.image)
                self.decodedBackdrop = NSImage(data: thumbnail.wash)
                self.decodedPalette = thumbnail.palette
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                // Artwork failure never affects audio; both surfaces use the cozy fallback.
                self.image = nil; self.isLoading = false
            }
        }
    }

    func chooseFolder(_ url: URL, preferences: AppPreferences) {
        guard preferences.canEdit else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.setFolder(bookmark: data, name: url.lastPathComponent)
            configure(preferences.snapshot.wallpaperConfiguration, preferences: preferences)
        } catch { self.error = "This folder couldn’t be opened. Choose it again to grant read-only access." }
    }

    func retry(preferences: AppPreferences) { loadFolder(preferences: preferences) }
    func next() {
        guard canAdvance, let configuration else { return }
        // Manual navigation can begin another cycle even when automatic looping is off.
        if let index = cycle.advance(loop: true, shuffled: configuration.order == .shuffle) {
            rotationFinished = false
            showImage(at: index)
        }
    }
    func shutdown() { loadTask?.cancel(); rotationTask?.cancel(); bundledBackdropTask?.cancel(); generation = UUID() }

    private func loadFolder(preferences: AppPreferences) {
        loadTask?.cancel(); rotationTask?.cancel(); generation = UUID()
        let token = generation
        image = nil; files = []; count = 0; error = nil; rotationFinished = false
        guard let bookmark = preferences.snapshot.folderBookmark else {
            isLoading = false
            error = "Choose a wallpaper folder in Settings. The cozy corner is shown until then."
            return
        }
        isLoading = true
        loadTask = Task { [weak self] in
            do {
                var stale = false
                let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                     relativeTo: nil, bookmarkDataIsStale: &stale)
                if stale {
                    let scoped = folder.startAccessingSecurityScopedResource()
                    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                    let fresh = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                       includingResourceValuesForKeys: nil, relativeTo: nil)
                    preferences.setFolder(bookmark: fresh, name: folder.lastPathComponent)
                    // Retain the refreshed identity so the shell does not restart this load.
                    self?.configuration = preferences.snapshot.wallpaperConfiguration
                }
                let operation = Task.detached { try Self.imageFiles(in: folder) }
                let files = try await withTaskCancellationHandler {
                    try await operation.value
                } onCancel: { operation.cancel() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.folder = folder; self.files = files; self.count = files.count
                self.cycle.reset(count: files.count, shuffled: self.configuration?.order == .shuffle)
                guard let index = self.cycle.current else {
                    self.isLoading = false
                    self.error = "No images found. Choose a folder containing JPEG, PNG, HEIC, or other supported images."
                    return
                }
                self.showImage(at: index)
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.isLoading = false
                self.error = "The wallpaper folder is unavailable. Reconnect the drive or choose the folder again."
            }
        }
    }

    private func showImage(at index: Int) {
        loadTask?.cancel(); rotationTask?.cancel(); generation = UUID()
        let token = generation
        guard let folder, files.indices.contains(index) else { return }
        let candidates = Array(files[index...] + files[..<index])
        isLoading = true
        loadTask = Task { [weak self] in
            let operation = Task.detached { try Self.thumbnail(in: folder, candidates: candidates) }
            do {
                let data = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                guard let image = NSImage(data: data.image) else { throw CocoaError(.fileReadCorruptFile) }
                self.image = image; self.decodedBackdrop = NSImage(data: data.wash)
                self.decodedPalette = data.palette
                self.isLoading = false; self.error = nil
                self.armRotation()
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.image = nil; self.isLoading = false
                self.error = "These images couldn’t be opened. Try another wallpaper folder."
            }
        }
    }

    private func armRotation() {
        rotationTask?.cancel()
        guard let configuration, configuration.source == .folder, configuration.automatic, count > 1 else { return }
        rotationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(configuration.seconds)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if let index = self.cycle.advance(loop: configuration.loop, shuffled: configuration.order == .shuffle) {
                self.showImage(at: index)
            } else { self.rotationFinished = true }
        }
    }

    nonisolated private static func imageFiles(in folder: URL) throws -> [URL] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let children = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey], options: [.skipsHiddenFiles])
        return try children.filter { url in
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey])
            return values.isRegularFile == true && values.isSymbolicLink != true && values.contentType?.conforms(to: .image) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated private static func artworkThumbnail(_ data: Data) throws -> DecodedArtwork {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw CocoaError(.fileReadCorruptFile) }
        return try decode(source)
    }

    nonisolated private static func decode(_ source: CGImageSource) throws -> DecodedArtwork {
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return try DecodedArtwork(image: ArtworkWash.png(thumbnail), wash: ArtworkWash.render(thumbnail),
                                  palette: ArtworkPaletteSampler.sample(thumbnail))
    }

    nonisolated private static func thumbnail(in folder: URL, candidates: [URL]) throws -> DecodedArtwork {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        for url in candidates {
            try Task.checkCancellation()
            // Recheck file types after scanning; ignore files changed into symlinks.
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
            if let decoded = try? decode(source) { return decoded }
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}
