import Foundation

@MainActor final class StubCatalog: MusicCatalog {
    let tracks = [
        MusicTrack(id: "first", title: "Soft light", artist: "A", permalink: nil),
        MusicTrack(id: "second", title: "Rain", artist: "B", permalink: nil)
    ]
    var channelSearches: [String] = []
    var searches = 0
    var resolutions: [String] = []
    var error: MusicFailure?
    var unavailable = Set<String>()
    var holdSearch = false
    var empty = false
    var pending: CheckedContinuation<[MusicTrack], Never>?
    func lofiTracks() async throws -> [MusicTrack] {
        searches += 1
        if let error { throw error }
        if empty { return [] }
        if holdSearch { return await withCheckedContinuation { pending = $0 } }
        return tracks
    }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] {
        channelSearches.append(channel.id)
        if holdSearch { return await withCheckedContinuation { pending = $0 } }
        return tracks
    }
    func streamURL(for track: MusicTrack) async throws -> URL {
        resolutions.append(track.id)
        if unavailable.contains(track.id) { throw MusicFailure.unavailable }
        guard let url = URL(string: "https://example.com/\(track.id).mp3") else { throw MusicFailure.unavailable }
        return url
    }
}

@MainActor final class StubPlayback: MusicPlayback {
    var volume: Float = 1
    var loads = 0
    var plays = 0
    var pauses = 0
    var stops = 0
    var autoplay = false
    var event: (@MainActor (MusicPlaybackEvent) -> Void)?
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {
        loads += 1
        self.autoplay = autoplay
        event = onEvent
    }
    func play() { plays += 1 }
    func pause() { pauses += 1 }
    func stop() { stops += 1 }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var status = 200
    @MainActor static var body = Data()
    @MainActor static var received: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            Self.received = request
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@main enum MusicPlayerChecks {
    static var checks = 0
    @MainActor static func main() async throws {
        let catalog = StubCatalog(), engine = StubPlayback()
        let model = MusicPlayerModel(catalog: catalog, playback: engine)
        expect(model.state == .idle && catalog.searches == 0, "No startup networking or autoplay")
        expect(engine.volume == 0.5, "Initial volume reaches player")
        model.volume = 2
        expect(model.volume == 1 && engine.volume == 1, "Clamp high volume")
        model.volume = -1
        expect(model.volume == 0 && engine.volume == 0, "Clamp low volume")
        model.volume = .nan
        expect(model.volume == 0.5 && engine.volume == 0.5, "Reject nonfinite volume")
        model.volume = 0.7
        model.toggleMute()
        expect(model.volume == 0 && engine.volume == 0, "Mute native player")
        model.toggleMute()
        expect(model.volume == 0.7, "Restore app-shared nonzero volume")
        model.togglePlayback()
        expect(model.state == .loading && model.wantsPlayback, "Play reports loading, not playing")
        await settle()
        expect(engine.loads == 1 && engine.autoplay && model.track?.id == "first", "Resolved track loads into native playback seam")
        expect(model.state == .loading, "Loading until actual AVPlayer event")
        engine.event?(.playing)
        expect(model.state == .playing, "Actual playing event drives state")
        model.togglePlayback()
        expect(model.state == .paused && !model.wantsPlayback && engine.pauses == 1, "Pause stops playback intent")
        engine.event?(.playing)
        expect(model.state == .paused && engine.pauses == 2, "Delayed playing event cannot undo pause")
        model.togglePlayback()
        expect(model.state == .loading && engine.plays == 1 && catalog.searches == 1, "Resume existing item without refetch")
        engine.event?(.playing)
        engine.event?(.waiting)
        expect(model.state == .loading, "Network stall shows buffering")
        engine.event?(.playing)
        let oldEvent = engine.event
        model.next()
        await settle()
        expect(model.track?.id == "second" && engine.autoplay, "Next retains playing intent")
        oldEvent?(.failed)
        expect(model.state == .loading, "Old item's failure is ignored")
        engine.event?(.playing)
        model.togglePlayback()
        model.previous()
        await settle()
        expect(model.track?.id == "first" && !engine.autoplay && model.state == .paused, "Skipping while paused stays paused")
        engine.event?(.ended)
        expect(model.track?.id == "first", "End event while paused does not autoplay")
        model.togglePlayback()
        engine.event?(.playing)
        engine.event?(.ended)
        await settle()
        expect(model.track?.id == "second" && engine.autoplay, "Track completion advances queue")
        engine.event?(.playing)
        engine.event?(.ended)
        await settle()
        expect(model.track?.id == "first", "Queue wraps for continuous lofi")
        engine.event?(.failed)
        expect(model.state == .failed(.connection) && !model.wantsPlayback, "Playback failure is visible and stops intent")
        let count = catalog.resolutions.count
        model.retry()
        await settle()
        expect(catalog.resolutions.count == count + 1 && engine.autoplay, "Retry obtains a fresh signed URL")
        let lastEvent = engine.event
        model.shutdown()
        lastEvent?(.playing)
        expect(model.state == .idle && !model.wantsPlayback, "Shutdown ignores old callbacks")

        let canceledCatalog = StubCatalog(), canceledEngine = StubPlayback()
        canceledCatalog.holdSearch = true
        let canceled = MusicPlayerModel(catalog: canceledCatalog, playback: canceledEngine)
        canceled.togglePlayback()
        await settle()
        canceled.togglePlayback()
        canceledCatalog.pending?.resume(returning: canceledCatalog.tracks)
        await settle()
        expect(canceled.state == .paused && canceledEngine.loads == 0, "Cancel during discovery cannot start audio later")
        canceledCatalog.holdSearch = false
        canceled.togglePlayback()
        await settle()
        expect(canceledEngine.loads == 1, "Play recovers after canceled search")
        canceled.shutdown()

        let timeoutCatalog = StubCatalog(), timeoutEngine = StubPlayback()
        timeoutCatalog.holdSearch = true
        let timed = MusicPlayerModel(catalog: timeoutCatalog, playback: timeoutEngine, timeoutInterval: .milliseconds(25))
        timed.togglePlayback()
        try await Task.sleep(for: .milliseconds(80))
        expect(timed.state == .failed(.connection), "Watchdog turns stalled discovery into a retryable error")
        timeoutCatalog.pending?.resume(returning: timeoutCatalog.tracks)
        await settle()
        expect(timeoutEngine.loads == 0, "Timed-out discovery cannot restart playback")
        timed.shutdown()

        let raceCatalog = StubCatalog(), raceEngine = StubPlayback()
        let race = MusicPlayerModel(catalog: raceCatalog, playback: raceEngine)
        race.togglePlayback(); await settle(); raceEngine.event?(.playing)
        race.togglePlayback()
        race.next()
        race.togglePlayback()
        await settle()
        expect(race.track?.id == "second" && raceEngine.autoplay, "Play immediately after a paused skip keeps the newly selected track")
        race.shutdown()

        let emptyCatalog = StubCatalog()
        emptyCatalog.empty = true
        let empty = MusicPlayerModel(catalog: emptyCatalog, playback: StubPlayback())
        empty.togglePlayback(); await settle()
        expect(empty.state == .failed(.noTracks), "Empty catalog shows an actionable state")
        empty.shutdown()

        let missingCatalog = StubCatalog(), missingEngine = StubPlayback()
        missingCatalog.unavailable = ["first"]
        let missing = MusicPlayerModel(catalog: missingCatalog, playback: missingEngine)
        missing.togglePlayback()
        await settle()
        expect(missing.track?.id == "second" && missingEngine.loads == 1, "Skip stale unavailable search results")
        missing.shutdown()
        missingCatalog.unavailable = ["first", "second"]
        missing.togglePlayback()
        await settle()
        expect(missing.state == .failed(.unavailable), "Entire unavailable queue fails without looping")
        expect(missingCatalog.resolutions.count == 4, "Unavailable resolution attempts are bounded")
        missing.shutdown()
        let brokenCatalog = StubCatalog(), brokenEngine = StubPlayback()
        brokenCatalog.error = .connection
        let broken = MusicPlayerModel(catalog: brokenCatalog, playback: brokenEngine)
        broken.togglePlayback()
        await settle()
        expect(broken.state == .failed(.connection) && brokenEngine.loads == 0, "Connection failure appears without audio")
        brokenCatalog.error = nil
        broken.retry()
        await settle()
        expect(brokenEngine.loads == 1, "Discovery retries after connection failure")
        broken.shutdown()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = AudiusClient(session: session)
        let valid: [String: Any] = ["id":"abc12", "title":"Tea", "user":["name":"Artist"], "permalink":"/artist/tea", "is_available":true, "is_stream_gated":false, "access":["stream":true]]
        var gated = valid; gated["id"] = "gate"; gated["is_stream_gated"] = true
        var unavailable = valid; unavailable["id"] = "gone"; unavailable["is_available"] = false
        var denied = valid; denied["id"] = "denied"; denied["access"] = ["stream":false]
        var invalid = valid; invalid["id"] = "../escape"
        var deleted = valid; deleted["id"] = "deleted"; deleted["is_delete"] = true
        var unknown = valid; unknown["id"] = "unknown"; unknown.removeValue(forKey: "is_available")
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: ["data":[valid,valid,gated,unavailable,denied,invalid,deleted,unknown]])
        let tracks = try await api.lofiTracks()
        expect(tracks.count == 1 && tracks[0].id == "abc12", "Filter gated, unavailable, inaccessible, deleted, unknown and duplicate tracks")
        expect(tracks[0].permalink?.absoluteString == "https://audius.co/artist/tea", "Safe Audius attribution link")
        let parts = StubURLProtocol.received?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        expect(parts?.path == "/v1/tracks/search" && parts?.queryItems?.contains(URLQueryItem(name: "query", value: "lofi")) == true, "Search lofi using official REST path")
        expect(parts?.queryItems?.contains(URLQueryItem(name: "app_name", value: "Keep")) == true, "Identify app without secrets")
        StubURLProtocol.body = Data(#"{"data":"https://creator.example/tracks/audio?signature=temporary"}"#.utf8)
        let url = try await api.streamURL(for: tracks[0])
        expect(url.scheme == "https", "Accept HTTPS signed stream")
        expect(StubURLProtocol.received?.url?.path == "/v1/tracks/abc12/stream", "Resolve stream via Audius")
        do { _ = try await api.streamURL(for: MusicTrack(id: "../escape", title: "Bad", artist: "A", permalink: nil)); expect(false, "Reject stream path injection") }
        catch { expect(error as? MusicFailure == .unavailable, "Reject stream path injection") }
        StubURLProtocol.body = Data(#"{"data":"http://insecure.example/audio"}"#.utf8)
        do { _ = try await api.streamURL(for: tracks[0]); expect(false, "Reject insecure streams") }
        catch { expect(error as? MusicFailure == .unavailable, "Reject insecure streams") }
        for (status, expected) in [(404, MusicFailure.unavailable), (403, .unavailable), (429, .rateLimited), (503, .connection)] {
            StubURLProtocol.status = status
            do { _ = try await api.lofiTracks(); expect(false, "HTTP failure") }
            catch { expect(error as? MusicFailure == expected, "Map HTTP \(status) to actionable state") }
        }
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"data":{"id":"artist12","name":"Warm loops","handle":"warmloops"}}"#.utf8)
        let artist = try await api.resolveChannel(" https://audius.co/warmloops ")
        expect(artist.kind == .artist && artist.resourceID == "artist12" && artist.name == "Warm loops", "Resolve an artist profile from a single resource")
        expect(StubURLProtocol.received?.url?.path == "/v1/resolve", "Use official Audius URL resolution")
        StubURLProtocol.body = Data(#"{"data":[{"id":"list12","playlist_name":"Rainy windows","is_private":false}]}"#.utf8)
        let playlist = try await api.resolveChannel("https://audius.co/warmloops/playlist/rainy-windows")
        expect(playlist.kind == .playlist && playlist.name == "Rainy windows", "Resolve a playlist from an array resource")
        StubURLProtocol.body = Data(#"{"data":[{"id":"track12","title":"Track"}]}"#.utf8)
        do { _ = try await api.resolveChannel("https://audius.co/warmloops/a-track"); expect(false, "Reject track as channel") }
        catch { expect(error is ChannelFailure, "Reject a track URL as a saved channel") }
        StubURLProtocol.body = Data(#"{"data":[{"id":"list12","playlist_name":"Private","is_private":true}]}"#.utf8)
        do { _ = try await api.resolveChannel(playlist.url.absoluteString); expect(false, "Reject private playlist") }
        catch { expect(error is ChannelFailure, "Reject inaccessible playlists") }
        for link in ["http://audius.co/artist", "https://audius.co.evil.example/artist", "https://name:secret@audius.co/artist", "https://example.com/artist", "https://audius.co/"] {
            do { _ = try await api.resolveChannel(link); expect(false, "Reject untrusted link") }
            catch { expect(error is ChannelFailure, "Reject non-Audius or credential-bearing channel links") }
        }
        var artTrack = valid
        artTrack["user"] = ["name":"Warm loops", "id":"artist12", "handle":"warmloops"]
        artTrack["artwork"] = ["1000x1000":"http://insecure.example/art", "480x480":"https://images.example/art.jpg"]
        StubURLProtocol.body = try JSONSerialization.data(withJSONObject: ["data":[artTrack, gated]])
        let artistTracks = try await api.tracks(for: artist)
        expect(StubURLProtocol.received?.url?.path == "/v1/users/artist12/tracks", "Fetch the saved artist’s public tracks")
        expect(artistTracks.count == 1 && artistTracks.first?.artistChannel == artist, "Preserve artist metadata and stream-access filtering for channels")
        expect(artistTracks.first?.artworkURL?.absoluteString == "https://images.example/art.jpg", "Use safe HTTPS artwork with smaller-image fallback")
        _ = try await api.tracks(for: playlist)
        expect(StubURLProtocol.received?.url?.path == "/v1/playlists/list12/tracks", "Fetch saved playlist tracks")

        let sourceCatalog = StubCatalog(), sourceEngine = StubPlayback()
        let sourceModel = MusicPlayerModel(catalog: sourceCatalog, playback: sourceEngine)
        sourceModel.selectChannel(artist)
        expect(sourceCatalog.channelSearches.isEmpty && sourceModel.state == .idle, "Selecting a saved source does not autoplay or network")
        sourceModel.togglePlayback()
        await settle()
        expect(sourceCatalog.channelSearches == [artist.id] && sourceCatalog.searches == 0, "Play uses selected artist instead of default lofi discovery")
        let replacedEvent = sourceEngine.event
        sourceModel.selectChannel(playlist, autoplay: true)
        await settle()
        replacedEvent?(.playing)
        expect(sourceModel.state == .loading && sourceModel.selectedChannel == playlist, "Old artist callbacks cannot change the new playlist state")
        expect(sourceCatalog.channelSearches == [artist.id, playlist.id] && sourceEngine.autoplay, "Explicit saved-channel Play loads the playlist")
        sourceModel.selectChannel(nil)
        expect(sourceModel.queue.isEmpty && sourceModel.track == nil && !sourceModel.wantsPlayback, "Returning to all lofi releases the old source and item")
        sourceModel.togglePlayback()
        await settle()
        expect(sourceCatalog.searches == 1, "Default source restores lofi discovery")
        sourceModel.shutdown()

        let sourceSlow = StubCatalog(), sourceSlowEngine = StubPlayback()
        sourceSlow.holdSearch = true
        let sourceRace = MusicPlayerModel(catalog: sourceSlow, playback: sourceSlowEngine)
        sourceRace.selectChannel(artist, autoplay: true)
        await settle()
        sourceRace.selectChannel(playlist)
        sourceSlow.pending?.resume(returning: sourceSlow.tracks)
        await settle()
        expect(sourceSlowEngine.loads == 0 && sourceRace.state == .idle && sourceRace.selectedChannel == playlist, "Canceled artist discovery cannot replace selected playlist")
        sourceRace.shutdown()
        print("Passed \(checks) music checks")
    }
    @MainActor static func settle() async { try? await Task.sleep(for: .milliseconds(15)) }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
}
