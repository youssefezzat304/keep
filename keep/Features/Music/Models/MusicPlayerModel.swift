import Foundation
import Observation

@Observable
final class MusicPlayerModel {
    private(set) var state: MusicPlaybackState = .idle
    private(set) var track: MusicTrack?
    private(set) var wantsPlayback = false
    private(set) var selectedChannel: MusicChannel?
    private(set) var queue: [MusicTrack] = []
    var volume: Double = 0.5 {
        didSet {
            let clamped = volume.isFinite ? min(1, max(0, volume)) : 0.5
            if clamped != volume { volume = clamped }
            if clamped > 0 { unmutedVolume = clamped }
            playback.volume = Float(clamped)
        }
    }

    @ObservationIgnored private let catalog: any MusicCatalog
    @ObservationIgnored private let playback: any MusicPlayback
    @ObservationIgnored private let timeoutInterval: Duration
    private var unmutedVolume = 0.5
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var loadingTimeout: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var itemToken: UUID?
    private var index = 0
    private var hasItem = false

    convenience init() { self.init(catalog: AudiusClient(), playback: AVMusicPlayback()) }

    init(catalog: any MusicCatalog, playback: any MusicPlayback, timeoutInterval: Duration = .seconds(30)) {
        self.catalog = catalog
        self.playback = playback
        self.timeoutInterval = timeoutInterval
        playback.volume = Float(volume)
    }

    var canSkip: Bool { queue.count > 1 }

    func toggleMute() { volume = volume > 0 ? 0 : unmutedVolume }

    func togglePlayback() {
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

    func retry() { load(at: index, autoplay: true) }
    func next() { if canSkip { load(at: (index + 1) % queue.count, autoplay: wantsPlayback) } }
    func previous() { if canSkip { load(at: (index + queue.count - 1) % queue.count, autoplay: wantsPlayback) } }

    /// Source changes cancel both discovery and the replaced native item; they never start audio implicitly.
    func selectChannel(_ channel: MusicChannel?, autoplay: Bool = false) {
        shutdown()
        selectedChannel = channel
        queue = []; track = nil; index = 0
        if autoplay { load(at: 0, autoplay: true) }
    }

    func shutdown() {
        request?.cancel()
        loadingTimeout?.cancel()
        generation = UUID()
        playback.stop()
        wantsPlayback = false
        hasItem = false
        itemToken = nil
        state = .idle
    }

    private func load(at requestedIndex: Int, autoplay: Bool) {
        request?.cancel()
        loadingTimeout?.cancel()
        playback.stop()
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
