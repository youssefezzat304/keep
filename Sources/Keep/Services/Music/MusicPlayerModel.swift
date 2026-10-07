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
    private(set) var appleArtwork: Data?
    private(set) var applePosition: Double = 0
    private(set) var appleDuration: Double = 0
    private(set) var appleShuffled = false
    private(set) var appleRepeat: AppleMusicRepeat = .off
    private(set) var appleMusicAccess: AppleMusicAccess = .notChecked
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
    @ObservationIgnored private let appleRefreshInterval: Duration
    @ObservationIgnored private let appleRecoveryGrace: Duration
    private struct AppleRecovery {
        enum Purpose { case startingPlayback, refreshing }
        let purpose: Purpose
        let started: ContinuousClock.Instant
    }
    @ObservationIgnored private var appleRecovery: AppleRecovery?
    @ObservationIgnored private let isMusicRunning: @MainActor () -> Bool
    @ObservationIgnored private var accessGeneration = UUID()
    private var unmutedVolume = 0.5
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var loadingTimeout: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var itemToken: UUID?
    @ObservationIgnored private var appleRefresh: Task<Void, Never>?
    @ObservationIgnored private var volumeRequest: Task<Void, Never>?
    @ObservationIgnored private var appleRelease: Task<Void, Never>?
    private var appleMusicEngaged = false
    private var applePlayTarget: AppleMusicItem?
    private var index = 0
    private var hasItem = false

    convenience init(preferences: AppPreferences = AppPreferences()) {
        self.init(catalog: AudiusClient(), playback: AVMusicPlayback(), preferences: preferences)
    }

    init(catalog: any MusicCatalog, playback: any MusicPlayback, preferences: AppPreferences = AppPreferences(),
         appleMusic: any AppleMusicControlling = AppleMusicController(),
         launchAppleMusic: (@MainActor () async throws -> Void)? = nil, timeoutInterval: Duration = .seconds(30),
         appleRefreshInterval: Duration = .seconds(1), isMusicRunning: (@MainActor () -> Bool)? = nil,
         appleRecoveryGrace: Duration = .seconds(8)) {
        self.catalog = catalog
        self.playback = playback
        self.preferences = preferences
        self.appleMusic = appleMusic
        self.launchAppleMusic = launchAppleMusic ?? { try await Self.launchMusicIfNeeded() }
        self.timeoutInterval = timeoutInterval
        self.appleRefreshInterval = appleRefreshInterval
        self.appleRecoveryGrace = appleRecoveryGrace
        self.isMusicRunning = isMusicRunning ?? { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty }
        unmutedVolume = preferences.musicVolume > 0 ? preferences.musicVolume : 0.5
        playback.volume = Float(volume)
    }

    var canSkip: Bool { provider == .appleMusic ? appleMusicConnected && track != nil : queue.count > 1 }

    func toggleMute() { volume = volume > 0 ? 0 : unmutedVolume }

    func makeAppleLibrary() -> AppleMusicLibraryModel {
        AppleMusicLibraryModel(controller: appleMusic, launch: launchAppleMusic)
    }

    /// Settings can check existing access silently; requesting it never plays audio.
    func checkAppleMusicAccess(requestPermission: Bool = false) async {
        guard appleMusicAccess != .checking else { return }
        guard requestPermission || isMusicRunning() else { appleMusicAccess = .notChecked; return }
        let previousAccess = appleMusicAccess
        accessGeneration = UUID()
        let token = accessGeneration
        appleMusicAccess = .checking
        do {
            if requestPermission { try await launchAppleMusic() }
            try Task.checkCancellation()
            let access = await appleMusic.access(requestPermission: requestPermission)
            try Task.checkCancellation()
            guard accessGeneration == token else { return }
            appleMusicAccess = access
            if access == .denied || access == .notRequested, provider == .appleMusic {
                appleRefresh?.cancel()
                appleRecovery = nil
                appleMusicConnected = false
                wantsPlayback = false
                state = .failed(.appleMusicPermission)
            }
            if access == .allowed, (requestPermission || previousAccess != .allowed), provider == .appleMusic { await observeAppleMusic() }
        } catch {
            guard accessGeneration == token else { return }
            appleMusicAccess = Task.isCancelled ? .notChecked : .failed
        }
    }

    func openMusicAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"), NSWorkspace.shared.open(url) else {
            appleMusicAccess = .failed
            return
        }
    }

    /// Explicit Browse may observe Music's existing playback without taking ownership or starting audio.
    func observeAppleMusic() async {
        guard provider == .appleMusic, state != .loading else { return }
        let token = generation
        do {
            try await launchAppleMusic()
            try Task.checkCancellation()
            let snapshot = try await appleMusic.perform(.status)
            try Task.checkCancellation()
            guard generation == token, provider == .appleMusic else { return }
            appleMusicConnected = true
            applyApple(snapshot)
            appleRefresh?.cancel()
            refreshApple(token: token)
        } catch {
            guard !Task.isCancelled, generation == token, provider == .appleMusic else { return }
            handleAppleReadFailure(error)
            if error as? MusicFailure == .appleMusicPermission { appleMusicAccess = .denied }
            else { refreshApple(token: token) }
        }
    }

    func playAppleItem(_ item: AppleMusicItem) {
        guard preferences.canEdit else { return }
        selectProvider(.appleMusic)
        applePlayTarget = item
        performApple(.playItem(item))
    }

    func seekApple(to seconds: Double) {
        guard provider == .appleMusic, appleMusicConnected, appleDuration > 0, seconds.isFinite else { return }
        performApple(.seek(min(appleDuration, max(0, seconds))))
    }

    func toggleAppleShuffle() {
        guard provider == .appleMusic, appleMusicConnected else { return }
        performApple(.shuffle(!appleShuffled))
    }

    func cycleAppleRepeat() {
        guard provider == .appleMusic, appleMusicConnected else { return }
        performApple(.repeatMode(appleRepeat.next))
    }

    func togglePlayback() {
        if provider == .appleMusic {
            if !wantsPlayback { applePlayTarget = nil }
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

    func retry() {
        if provider == .appleMusic { performApple(applePlayTarget.map(AppleMusicCommand.playItem) ?? .play) }
        else { load(at: index, autoplay: true) }
    }
    func next() {
        guard canSkip else { return }
        if provider == .appleMusic { applePlayTarget = nil; performApple(.next) }
        else { load(at: (index + 1) % queue.count, autoplay: wantsPlayback) }
    }
    func previous() {
        guard canSkip else { return }
        if provider == .appleMusic { applePlayTarget = nil; performApple(.previous) }
        else { load(at: (index + queue.count - 1) % queue.count, autoplay: wantsPlayback) }
    }

    func selectProvider(_ provider: MusicProvider) {
        guard preferences.canEdit, provider != self.provider else { return }
        shutdown()
        preferences.musicProvider = provider
        queue = []; track = nil; index = 0
    }

    /// An explicit list selection plays a saved source, or All Lofi when nil.
    func playAudiusSource(_ channel: MusicChannel?) {
        guard preferences.canEdit else { return }
        selectProvider(.audius)
        preferences.selectChannel(channel)
        if selectedChannel?.id != channel?.id { selectChannel(channel, autoplay: true) }
        else if case .failed = state { retry() }
        else if !wantsPlayback { togglePlayback() }
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
        accessGeneration = UUID()
        if appleMusicAccess == .checking { appleMusicAccess = .notChecked }
        request?.cancel()
        loadingTimeout?.cancel()
        appleRefresh?.cancel()
        volumeRequest?.cancel()
        let releasePlayback = appleMusicEngaged
        appleRelease = Task { [appleMusic] in
            await appleMusic.invalidateLibraryCache()
            if releasePlayback {
                do { _ = try await appleMusic.perform(.pause) }
                catch { NSLog("Keep: Music pause on release failed (%@)", String(describing: error)) }
            }
        }
        appleMusicEngaged = false
        appleRecovery = nil
        applePlayTarget = nil
        appleMusicConnected = false
        appleArtwork = nil; applePosition = 0; appleDuration = 0
        appleShuffled = false; appleRepeat = .off
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
        let startsPlayback: Bool
        switch command { case .play, .playItem: startsPlayback = true; default: startsPlayback = false }
        appleRecovery = AppleRecovery(purpose: startsPlayback || ((command == .next || command == .previous) && resumeAfterSkip)
            ? .startingPlayback : .refreshing, started: .now)
        if startsPlayback { wantsPlayback = true }
        else if command == .pause { wantsPlayback = false }
        state = .loading
        request = Task { [weak self, appleMusic] in
            var commandAttempted = false
            do {
                guard let self else { return }
                await self.appleRelease?.value
                try Task.checkCancellation()
                if startsPlayback {
                    try await self.launchAppleMusic()
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    // Apply the saved app volume only after the user's explicit Play.
                    _ = try await appleMusic.perform(.volume(Int((self.volume * 100).rounded())))
                }
                try Task.checkCancellation()
                if startsPlayback { self.appleMusicEngaged = true }
                commandAttempted = true
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
                if commandAttempted {
                    self.handleAppleReadFailure(error)
                    if error as? MusicFailure != .appleMusicPermission { self.refreshApple(token: token) }
                } else {
                    self.appleRecovery = nil
                    self.wantsPlayback = false
                    self.state = .failed((error as? MusicFailure) ?? .appleMusicConnection)
                }
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
        if let recovery = appleRecovery, recovery.purpose == .startingPlayback, snapshot.state != .playing {
            if recovery.started.duration(to: .now) < appleRecoveryGrace { state = .loading }
            else { wantsPlayback = false; state = .failed(.appleMusicConnection) }
            return
        }
        appleRecovery = nil
        wantsPlayback = snapshot.state == .playing
        state = wantsPlayback ? .playing : .paused
        if let title = snapshot.title {
            track = MusicTrack(id: snapshot.trackID ?? "apple-music-current", title: title,
                artist: snapshot.artist ?? "Apple Music", permalink: URL(string: "music://"))
            appleArtwork = snapshot.artwork
            applePosition = snapshot.position
            appleDuration = snapshot.duration
            appleShuffled = snapshot.shuffled
            appleRepeat = snapshot.repeatMode
        } else if snapshot.state == .stopped {
            track = nil; appleArtwork = nil; applePosition = 0; appleDuration = 0
        }
    }

    private func handleAppleReadFailure(_ error: Error) {
        appleMusicConnected = false
        let failure = (error as? MusicFailure) ?? .appleMusicConnection
        guard failure != .appleMusicPermission else {
            appleRecovery = nil
            wantsPlayback = false
            appleMusicAccess = .denied
            state = .failed(failure)
            return
        }
        if appleRecovery == nil { appleRecovery = AppleRecovery(purpose: .refreshing, started: .now) }
        if let recovery = appleRecovery, recovery.started.duration(to: .now) < appleRecoveryGrace {
            state = .loading
        } else {
            wantsPlayback = false
            state = .failed(failure)
        }
    }

    private func refreshApple(token: UUID) {
        appleRefresh?.cancel()
        appleRefresh = Task { [weak self, appleMusic, appleRefreshInterval] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    let withinGrace = self.map { owner in
                        owner.appleRecovery.map { $0.started.duration(to: .now) < owner.appleRecoveryGrace } ?? false
                    } ?? false
                    try await Task.sleep(for: appleRefreshInterval * (withinGrace ? 1 : min(15, 1 << min(failures, 4))))
                    let snapshot = try await appleMusic.perform(.status)
                    try Task.checkCancellation()
                    guard let self, self.generation == token else { return }
                    self.applyApple(snapshot)
                    self.appleMusicConnected = true
                    failures = 0
                } catch {
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    self.handleAppleReadFailure(error)
                    if error as? MusicFailure == .appleMusicPermission {
                        self.appleMusicAccess = .denied
                        return
                    }
                    // Music may briefly reject reads while a cloud track loads.
                    // Keep observing its actual state instead of requiring another Play.
                    failures += 1
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
