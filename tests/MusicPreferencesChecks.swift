import Foundation

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
    func setFailure(_ failure: MusicFailure?) { self.failure = failure }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        commands.append(command)
        if let failure { throw failure }
        switch command {
        case .play, .next, .previous: state = .playing
        case .pause: state = .paused
        case .volume, .status: break
        }
        return AppleMusicSnapshot(state: state, title: state == .stopped ? nil : "Quiet song", artist: "Preview artist")
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
        print("Passed \(checks) music/preferences checks (silent fixtures)")
    }
}
