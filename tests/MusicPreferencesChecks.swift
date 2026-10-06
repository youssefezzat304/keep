import Foundation
import AppKit

private struct SilentCatalog: MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack] { throw MusicFailure.noTracks }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { throw MusicFailure.noTracks }
    func streamURL(for track: MusicTrack) async throws -> URL { throw MusicFailure.unavailable }
}

private final class SilentPlayback: MusicPlayback {
    var volume: Float = 0
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {}
    func play() {}
    func pause() {}
    func stop() {}
}

private actor SilentMusic: AppleMusicControlling {
    private(set) var commands: [AppleMusicCommand] = []
    private var state: AppleMusicSnapshot.State = .stopped
    var failure: MusicFailure?
    private var shuffled = false
    private var repeated: AppleMusicRepeat = .off
    private var position = 12.0
    func setFailure(_ failure: MusicFailure?) { self.failure = failure }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        commands.append(command)
        if let failure { throw failure }
        switch command {
        case .play, .next, .previous: state = .playing
        case .pause: state = .paused
        case .playItem: state = .playing
        case .seek(let seconds): position = seconds
        case .shuffle(let enabled): shuffled = enabled
        case .repeatMode(let mode): repeated = mode
        case .volume, .status: break
        }
        return AppleMusicSnapshot(state: state, title: state == .stopped ? nil : "Quiet song", artist: "Preview artist",
            trackID: "silent-song", artwork: state == .stopped ? nil : Data([1, 2, 3]),
            position: position, duration: 180, shuffled: shuffled, repeatMode: repeated)
    }
}

private actor LibraryFixture: AppleMusicControlling {
    private(set) var requests: [AppleMusicLibraryRequest] = []
    var failure: MusicFailure?
    func setFailure(_ value: MusicFailure?) { failure = value }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        AppleMusicSnapshot(state: .stopped, title: nil, artist: nil)
    }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage {
        requests.append(request)
        if let failure { throw failure }
        let item = AppleMusicItem(nativeID: 1, kind: request.kind, title: request.query.isEmpty ? "First" : request.query, artist: "Artist")
        if request.offset == 0 { return AppleMusicLibraryPage(items: [item, item], hasMore: true) }
        return AppleMusicLibraryPage(items: [item, AppleMusicItem(nativeID: 2, kind: request.kind, title: "Second", artist: "Artist")], hasMore: false)
    }
}

private actor DelayedLibrary: AppleMusicControlling {
    private var pending: CheckedContinuation<AppleMusicLibraryPage, Never>?
    var isPending: Bool { pending != nil }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        AppleMusicSnapshot(state: .stopped, title: nil, artist: nil)
    }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage {
        if request.query == "old" { return await withCheckedContinuation { pending = $0 } }
        return AppleMusicLibraryPage(items: [AppleMusicItem(nativeID: 2, kind: .songs, title: "New search", artist: "Artist")], hasMore: false)
    }
    func finish() {
        pending?.resume(returning: AppleMusicLibraryPage(items: [AppleMusicItem(nativeID: 1, kind: .songs, title: "Stale search", artist: "Artist")], hasMore: false))
        pending = nil
    }
}

private actor DelayedMusic: AppleMusicControlling {
    private var pending: CheckedContinuation<AppleMusicSnapshot, Never>?
    var isPending: Bool { pending != nil }
    func finishPlay() {
        pending?.resume(returning: AppleMusicSnapshot(state: .playing, title: "Stale track", artist: "Old request"))
        pending = nil
    }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        if command == .play { return await withCheckedContinuation { pending = $0 } }
        return AppleMusicSnapshot(state: .stopped, title: nil, artist: nil)
    }
}

@main enum MusicPreferencesChecks {
    private static var checks = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }
    private static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Music state did not settle")
    }
    static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--reload" {
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]) else { fatalError("No child defaults suite") }
            let reopened = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
            precondition(reopened.musicVolume == 0.27 && reopened.musicProvider == .appleMusic, "Cross-process provider/volume reload")
            return
        }
        let suite = "keep.music-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        let native = SilentMusic()
        let playback = SilentPlayback()
        let model = MusicPlayerModel(catalog: SilentCatalog(), playback: playback, preferences: preferences,
            appleMusic: native, launchAppleMusic: {})
        model.volume = 0.27
        expect(abs(playback.volume - 0.27) < 0.001, "Apply volume to Audius")
        let reopened = AppPreferences(persistence: persistence)
        expect(reopened.musicVolume == 0.27, "Restore exact last volume from disk")
        model.toggleMute()
        let muted = try persistence.load()
        expect(muted.musicVolume == 0, "Mute survives relaunch")
        model.toggleMute()
        expect(model.volume == 0.27, "Unmute restores the previous nonzero level")
        model.selectProvider(.appleMusic)
        let beforePlay = await native.commands
        expect(beforePlay.isEmpty && model.state == .idle, "Provider selection performs no launch, authorization, or playback")
        let selected = try persistence.load()
        expect(selected.musicProvider == .appleMusic, "Provider preference survives relaunch")
        defaults.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--reload", suite]
        try child.run()
        child.waitUntilExit()
        expect(child.terminationStatus == 0, "A separate process restores the provider and last volume")
        let restoredNative = SilentMusic()
        let restored = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(),
            preferences: AppPreferences(persistence: persistence), appleMusic: restoredNative, launchAppleMusic: {})
        let restoredCommands = await restoredNative.commands
        expect(restored.provider == .appleMusic && restored.volume == 0.27 && restoredCommands.isEmpty, "Relaunch restores provider and volume without contacting Music")
        model.togglePlayback()
        try await waitUntil { model.state == .playing }
        let playCommands = await native.commands
        expect(playCommands.prefix(2) == [.volume(27), .play], "Apple Music receives the saved volume before explicit Play")
        expect(model.track?.title == "Quiet song" && model.appleMusicConnected, "Display actual Apple Music metadata/state")
        model.togglePlayback()
        try await waitUntil { model.state == .paused }
        model.next()
        try await waitUntil { model.state == .paused }
        let skipCommands = await native.commands
        expect(skipCommands.suffix(2) == [.next, .pause], "Skip preserves paused intent")
        model.volume = 0.63
        try await Task.sleep(for: .milliseconds(200))
        let volumeCommands = await native.commands
        expect(volumeCommands.last == .volume(63), "Volume controls Music without changing system output volume")
        model.selectProvider(.audius)
        await model.shutdown()?.value
        let releaseCommands = await native.commands
        expect(releaseCommands.last == .pause && model.state == .idle, "Switching provider releases the owned Apple Music session")

        // Existing preference archives omit the new optional fields.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.snapshot)) as? [String: Any] ?? [:]
        old.removeValue(forKey: "musicVolume"); old.removeValue(forKey: "musicProvider")
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: persistence.key)
        let migrated = AppPreferences(persistence: persistence)
        expect(migrated.canEdit && migrated.musicVolume == 0.5 && migrated.musicProvider == .audius, "Legacy archives load with safe defaults")
        old["musicVolume"] = 1.5
        let invalid = try JSONSerialization.data(withJSONObject: old)
        defaults.set(invalid, forKey: persistence.key)
        let blocked = AppPreferences(persistence: persistence)
        blocked.musicVolume = 0.2
        expect(!blocked.canEdit && defaults.data(forKey: persistence.key) == invalid, "Invalid volume blocks edits without overwriting preferences")

        let denied = SilentMusic()
        await denied.setFailure(.appleMusicPermission)
        let deniedModel = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(),
            appleMusic: denied, launchAppleMusic: {})
        deniedModel.selectProvider(.appleMusic)
        deniedModel.togglePlayback()
        try await waitUntil { deniedModel.state == .failed(.appleMusicPermission) }
        expect(!deniedModel.wantsPlayback && !deniedModel.appleMusicConnected, "Permission denial never claims playback")
        await denied.setFailure(nil)
        deniedModel.retry()
        try await waitUntil { deniedModel.state == .playing }
        await deniedModel.shutdown()?.value

        let delayed = DelayedMusic()
        let canceled = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(),
            appleMusic: delayed, launchAppleMusic: {})
        canceled.selectProvider(.appleMusic)
        canceled.togglePlayback()
        for _ in 0..<100 {
            if await delayed.isPending { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await delayed.isPending else { preconditionFailure("Delayed play did not start") }
        canceled.selectProvider(.audius)
        await delayed.finishPlay()
        await canceled.shutdown()?.value
        try await Task.sleep(for: .milliseconds(20))
        expect(canceled.provider == .audius && canceled.state == .idle && canceled.track == nil, "Late Apple Music replies cannot replace the chosen provider or restart playback")
        try await libraryChecks()
        try await artworkChecks()
        print("Passed \(checks) music/preferences/library/artwork checks (silent fixtures)")
    }

    private static func libraryChecks() async throws {
        let fixture = LibraryFixture()
        var launches = 0
        let library = AppleMusicLibraryModel(controller: fixture, launch: { launches += 1 })
        expect(library.state == .idle && launches == 0, "Constructing the library remains passive")
        await library.load(AppleMusicLibraryRequest())
        expect(library.state == .ready && library.items.count == 1 && library.hasMore, "Deduplicate a library page without losing pagination")
        await library.load(AppleMusicLibraryRequest(offset: 50), append: true)
        expect(library.items.map(\.nativeID) == [1, 2] && !library.hasMore, "Append the next page without duplicates")
        let requests = await fixture.requests
        expect(requests.map(\.offset) == [0, 50], "Paging uses bounded native batches")
        let list = AppleMusicItem(nativeID: 7, kind: .playlists, title: "Focus", artist: "Playlist")
        await library.load(AppleMusicLibraryRequest(query: "a user's \"quoted\" search", playlist: list))
        let forwarded = await fixture.requests.last
        expect(forwarded?.playlist == list && forwarded?.query == "a user's \"quoted\" search", "Keep search text as typed data and retain playlist scope")
        await fixture.setFailure(.appleMusicPermission)
        await library.load(AppleMusicLibraryRequest())
        expect(library.state == .failed(.appleMusicPermission) && library.items.isEmpty, "Denied library access clears stale results and offers Retry")
        await fixture.setFailure(nil)
        await library.load(AppleMusicLibraryRequest(kind: .playlists))
        expect(library.state == .ready && library.items.first?.kind == .playlists, "Library retry can recover and switch to playlists")
        let delayed = DelayedLibrary()
        let search = AppleMusicLibraryModel(controller: delayed, launch: {})
        let old = Task { await search.load(AppleMusicLibraryRequest(query: "old")) }
        for _ in 0..<100 {
            if await delayed.isPending { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await delayed.isPending else { preconditionFailure("Delayed search did not start") }
        await search.load(AppleMusicLibraryRequest(query: "new"))
        await delayed.finish(); await old.value
        expect(search.items.first?.title == "New search", "Older search responses cannot replace current results")
        let close = Task { await search.load(AppleMusicLibraryRequest(query: "old")) }
        for _ in 0..<100 {
            if await delayed.isPending { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        search.cancel(); close.cancel(); await delayed.finish(); await close.value
        expect(search.state == .idle, "Dismissed searches cannot repopulate library state")

        let native = SilentMusic()
        let model = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(), appleMusic: native, launchAppleMusic: {})
        model.volume = 0.35
        model.playAppleItem(list)
        try await waitUntil { model.state == .playing }
        let commands = await native.commands
        expect(commands.prefix(2) == [.volume(35), .playItem(list)], "Library Play selects Music and restores volume before playing the native item")
        expect(model.track?.id == "silent-song" && model.appleArtwork == Data([1, 2, 3]) && model.appleDuration == 180,
            "Now playing carries stable identity, available artwork, and timing")
        model.seekApple(to: 999)
        try await waitUntil { model.state == .playing && model.applePosition == 180 }
        let seek = await native.commands
        expect(seek.last == .seek(180), "Seeking stays within the actual track duration")
        let count = seek.count
        model.seekApple(to: .nan)
        let afterInvalid = await native.commands
        expect(afterInvalid.count == count, "Reject invalid seek values without native calls")
        model.togglePlayback(); try await waitUntil { model.state == .paused }
        model.toggleAppleShuffle(); try await waitUntil { model.state == .paused && model.appleShuffled }
        expect(!model.wantsPlayback, "Shuffle changes preserve paused intent")
        model.cycleAppleRepeat(); try await waitUntil { model.state == .paused && model.appleRepeat == .all }
        model.cycleAppleRepeat(); try await waitUntil { model.state == .paused && model.appleRepeat == .one }
        model.cycleAppleRepeat(); try await waitUntil { model.state == .paused && model.appleRepeat == .off }
        expect(!model.wantsPlayback, "Repeat cycles off/all/one without starting playback")
        model.selectProvider(.audius); await model.shutdown()?.value
        expect(model.appleArtwork == nil && model.appleDuration == 0, "Provider changes clear Apple artwork and timing")
        let retryNative = SilentMusic()
        await retryNative.setFailure(.appleMusicConnection)
        let retry = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(), appleMusic: retryNative, launchAppleMusic: {})
        retry.playAppleItem(list)
        try await waitUntil { retry.state == .failed(.appleMusicConnection) }
        await retryNative.setFailure(nil)
        retry.retry()
        try await waitUntil { retry.state == .playing }
        let retriedCommands = await retryNative.commands
        expect(retriedCommands.suffix(2) == [.volume(50), .playItem(list)], "Retry preserves the failed library selection")
        await retry.shutdown()?.value
        let external = SilentMusic()
        _ = try await external.perform(.play) // Simulate Music already playing before Keep connects.
        let observer = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(), appleMusic: external, launchAppleMusic: {})
        observer.selectProvider(.appleMusic)
        await observer.observeAppleMusic()
        expect(observer.state == .playing && observer.track?.title == "Quiet song", "Explicit Browse observes an existing Music selection")
        await observer.shutdown()?.value
        let observedCommands = await external.commands
        expect(observedCommands == [.play, .status], "Browse neither changes volume nor claims/pauses externally started playback")
    }

    private static func artworkChecks() async throws {
        let wallpapers = WallpaperLibrary()
        let preferences = AppPreferences()
        wallpapers.configure(preferences.snapshot.wallpaperConfiguration, preferences: preferences)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                bytesPerRow: 16, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { preconditionFailure("No image fixture") }
        context.setFillColor(red: 0.8, green: 0.4, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        guard let cgImage = context.makeImage() else { preconditionFailure("No CG image fixture") }
        let png = try ArtworkWash.png(cgImage)
        wallpapers.setArtwork(url: nil, data: png)
        try await waitUntil { wallpapers.trackImage != nil }
        expect(wallpapers.image == nil && wallpapers.trackImage != nil, "Library cover art is available without replacing a chosen wallpaper")
        let cover = wallpapers.trackImage
        preferences.wallpaperSource = .audius
        wallpapers.configure(preferences.snapshot.wallpaperConfiguration, preferences: preferences)
        try await waitUntil { !wallpapers.isLoading }
        expect(wallpapers.image != nil && wallpapers.backdrop(for: .audius) != nil && wallpapers.palette(for: .audius) != nil,
            "Native artwork bytes feed the shared image, backdrop, and palette without a URL")
        expect(wallpapers.image === cover, "Selecting Track artwork reuses the library's decoded cover")
        let image = wallpapers.image
        wallpapers.setArtwork(url: nil, data: png)
        expect(wallpapers.image === image && !wallpapers.isLoading, "Unchanged native artwork is decoded only once")
        wallpapers.setArtwork(url: nil, data: Data([0, 1]))
        try await waitUntil { !wallpapers.isLoading }
        expect(wallpapers.image == nil, "Corrupt native artwork uses the fallback without affecting audio")
        wallpapers.setArtwork(url: nil, data: png)
        wallpapers.setArtwork(url: nil, data: nil)
        try await Task.sleep(for: .milliseconds(50))
        expect(wallpapers.image == nil, "Replaced artwork decoding cannot restore a stale image")
        wallpapers.shutdown()
    }
}
