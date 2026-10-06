import Foundation
import Observation
import AppKit

@Observable
final class MusicPlayerModel {
    private(set) var state: MusicPlaybackState = .idle
    private(set) var track: MusicTrack?
    private(set) var wantsPlayback = false
    private(set) var selectedChannel: MusicChannel?
    private(set) var queue: [MusicTrack] = []
    var provider: MusicProvider { preferences.musicProvider }
    private(set) var appleMusicConnected = false
    var volume: Double {
        get { preferences.musicVolume }
        set {
            guard preferences.canEdit else { return }
            preferences.musicVolume = newValue
            let clamped = preferences.musicVolume
            if clamped > 0 { unmutedVolume = clamped }
            playback.volume = Float(clamped)
            if provider == .appleMusic, appleMusicConnected { updateAppleVolume() }
        }
    }

    @ObservationIgnored private let catalog: any MusicCatalog
    @ObservationIgnored private let playback: any MusicPlayback
    @ObservationIgnored private let appleMusic: any AppleMusicControlling
    @ObservationIgnored private let launchAppleMusic: @MainActor () async throws -> Void
    private let preferences: AppPreferences
    @ObservationIgnored private let timeoutInterval: Duration
    private var unmutedVolume = 0.5
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var loadingTimeout: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var itemToken: UUID?
    @ObservationIgnored private var appleRefresh: Task<Void, Never>?
    @ObservationIgnored private var volumeRequest: Task<Void, Never>?
    @ObservationIgnored private var appleRelease: Task<Void, Never>?
    private var appleMusicEngaged = false
    private var index = 0
    private var hasItem = false

    convenience init(preferences: AppPreferences = AppPreferences()) {
        self.init(catalog: AudiusClient(), playback: AVMusicPlayback(), preferences: preferences)
    }

    init(catalog: any MusicCatalog, playback: any MusicPlayback, preferences: AppPreferences = AppPreferences(),
         appleMusic: any AppleMusicControlling = AppleMusicController(),
         launchAppleMusic: (@MainActor () async throws -> Void)? = nil, timeoutInterval: Duration = .seconds(30)) {
        self.catalog = catalog
        self.playback = playback
        self.preferences = preferences
        self.appleMusic = appleMusic
        self.launchAppleMusic = launchAppleMusic ?? { try await Self.launchMusicIfNeeded() }
        self.timeoutInterval = timeoutInterval
        unmutedVolume = preferences.musicVolume > 0 ? preferences.musicVolume : 0.5
        playback.volume = Float(volume)
    }

    var canSkip: Bool { provider == .appleMusic ? appleMusicConnected && track != nil : queue.count > 1 }

    func toggleMute() { volume = volume > 0 ? 0 : unmutedVolume }

    func togglePlayback() {
        if provider == .appleMusic {
            performApple(wantsPlayback ? .pause : .play)
            return
        }
        playback.volume = Float(volume)
        if wantsPlayback {
            wantsPlayback = false
            request?.cancel()
            generation = UUID()
            loadingTimeout?.cancel()
            playback.pause()
            state = .paused
        } else if hasItem {
            wantsPlayback = true
            state = .loading
            armTimeout()
            playback.play()
        } else { load(at: index, autoplay: true) }
    }

    func retry() { if provider == .appleMusic { performApple(.play) } else { load(at: index, autoplay: true) } }
    func next() {
        guard canSkip else { return }
        if provider == .appleMusic { performApple(.next) }
        else { load(at: (index + 1) % queue.count, autoplay: wantsPlayback) }
    }
    func previous() {
        guard canSkip else { return }
        if provider == .appleMusic { performApple(.previous) }
        else { load(at: (index + queue.count - 1) % queue.count, autoplay: wantsPlayback) }
    }

    func selectProvider(_ provider: MusicProvider) {
        guard preferences.canEdit, provider != self.provider else { return }
        shutdown()
        preferences.musicProvider = provider
        queue = []; track = nil; index = 0
    }

    func openAppleMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            state = .failed(.appleMusicConnection)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Source changes cancel both discovery and the replaced native item; they never start audio implicitly.
    func selectChannel(_ channel: MusicChannel?, autoplay: Bool = false) {
        // Explicit saved-source Play returns to Audius; restoration stays passive.
        if autoplay, provider != .audius { selectProvider(.audius) }
        shutdown()
        selectedChannel = channel
        queue = []; track = nil; index = 0
        if autoplay, provider == .audius { load(at: 0, autoplay: true) }
    }

    @discardableResult
    func shutdown() -> Task<Void, Never>? {
        request?.cancel()
        loadingTimeout?.cancel()
        appleRefresh?.cancel()
        volumeRequest?.cancel()
        if appleMusicEngaged {
            appleRelease = Task { [appleMusic] in
                do { _ = try await appleMusic.perform(.pause) }
                catch { NSLog("Keep: Music pause on release failed (%@)", String(describing: error)) }
            }
        }
        appleMusicEngaged = false
        appleMusicConnected = false
        generation = UUID()
        playback.stop()
        wantsPlayback = false
        hasItem = false
        itemToken = nil
        state = .idle
        return appleRelease
    }

    private func performApple(_ command: AppleMusicCommand) {
        request?.cancel()
        appleRefresh?.cancel()
        generation = UUID()
        let token = generation
        let resumeAfterSkip = wantsPlayback
        wantsPlayback = command != .pause
        state = .loading
        request = Task { [weak self, appleMusic] in
            do {
                guard let self else { return }
                await self.appleRelease?.value
                try Task.checkCancellation()
                if command == .play {
                    try await self.launchAppleMusic()
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    // Apply the saved app volume only after the user's explicit Play.
                    _ = try await appleMusic.perform(.volume(Int((self.volume * 100).rounded())))
                }
                try Task.checkCancellation()
                if command == .play { self.appleMusicEngaged = true }
                var snapshot = try await appleMusic.perform(command)
                if (command == .next || command == .previous), !resumeAfterSkip {
                    snapshot = try await appleMusic.perform(.pause)
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                self.appleMusicConnected = true
                self.applyApple(snapshot)
                self.refreshApple(token: token)
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.wantsPlayback = false
                self.state = .failed((error as? MusicFailure) ?? .appleMusicConnection)
                if error as? MusicFailure == .appleMusicPermission { self.appleMusicEngaged = false }
            }
        }
    }

    private static func launchMusicIfNeeded() async throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { throw MusicFailure.appleMusicConnection }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func applyApple(_ snapshot: AppleMusicSnapshot) {
        wantsPlayback = snapshot.state == .playing
        state = wantsPlayback ? .playing : .paused
        if let title = snapshot.title {
            track = MusicTrack(id: "apple-music-current", title: title,
                artist: snapshot.artist ?? "Apple Music", permalink: URL(string: "music://"))
        } else if snapshot.state == .stopped { track = nil }
    }

    private func refreshApple(token: UUID) {
        appleRefresh = Task { [weak self, appleMusic] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                    let snapshot = try await appleMusic.perform(.status)
                    try Task.checkCancellation()
                    guard let self, self.generation == token else { return }
                    self.applyApple(snapshot)
                } catch {
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.appleMusicConnected = false
                    self.wantsPlayback = false
                    self.state = .failed((error as? MusicFailure) ?? .appleMusicConnection)
                    return
                }
            }
        }
    }

    private func updateAppleVolume() {
        volumeRequest?.cancel()
        let level = Int((volume * 100).rounded())
        let token = generation
        volumeRequest = Task { [weak self, appleMusic] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                _ = try await appleMusic.perform(.volume(level))
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.state = .failed((error as? MusicFailure) ?? .appleMusicConnection)
            }
        }
    }

    private func load(at requestedIndex: Int, autoplay: Bool) {
        request?.cancel()
        loadingTimeout?.cancel()
        playback.stop()
        playback.volume = Float(volume)
        hasItem = false
        itemToken = nil
        wantsPlayback = autoplay
        index = requestedIndex
        if queue.indices.contains(index) { track = queue[index] }
        state = .loading
        generation = UUID()
        let token = generation
        let channel = selectedChannel
        if autoplay { armTimeout() }
        request = Task { [weak self, catalog] in
            do {
                let tracks: [MusicTrack]
                if let self, !self.queue.isEmpty { tracks = self.queue }
                else if let channel { tracks = try await catalog.tracks(for: channel) }
                else { tracks = try await catalog.lofiTracks() }
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.queue = tracks
                guard !tracks.isEmpty else { throw MusicFailure.noTracks }
                // Metadata can outlive deleted audio: skip unavailable streams, with a bounded attempt count.
                for offset in 0..<tracks.count {
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    let selected = (requestedIndex + offset) % tracks.count
                    self.index = selected
                    self.track = tracks[selected]
                    do {
                        let url = try await catalog.streamURL(for: tracks[selected])
                        try Task.checkCancellation()
                        guard self.generation == token else { return }
                        self.hasItem = true
                        self.itemToken = token
                        self.state = autoplay ? .loading : .paused
                        self.playback.load(url, autoplay: autoplay) { [weak self] event in
                            self?.receive(event, itemToken: token)
                        }
                        if autoplay { self.armTimeout() }
                        return
                    } catch MusicFailure.unavailable { continue }
                }
                throw MusicFailure.unavailable
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.fail((error as? MusicFailure) ?? .connection)
            }
        }
    }

    private func receive(_ event: MusicPlaybackEvent, itemToken: UUID) {
        // Pause cancels requests but retains the current AVPlayer item and its callbacks.
        guard hasItem, self.itemToken == itemToken, state != .idle else { return }
        switch event {
        case .failed: fail(.connection)
        case .playing:
            guard wantsPlayback else { playback.pause(); return }
            loadingTimeout?.cancel()
            state = .playing
        case .waiting:
            guard wantsPlayback else { return }
            state = .loading
            armTimeout()
        case .ended:
            guard wantsPlayback else { return }
            load(at: queue.isEmpty ? 0 : (index + 1) % queue.count, autoplay: true)
        }
    }

    private func fail(_ error: MusicFailure) {
        request?.cancel()
        generation = UUID()
        loadingTimeout?.cancel()
        playback.stop()
        hasItem = false
        itemToken = nil
        wantsPlayback = false
        state = .failed(error)
    }

    private func armTimeout() {
        loadingTimeout?.cancel()
        loadingTimeout = Task { [weak self, timeoutInterval] in
            do { try await Task.sleep(for: timeoutInterval) } catch { return }
            guard let self, self.state == .loading, self.wantsPlayback else { return }
            self.fail(.connection)
        }
    }
}
