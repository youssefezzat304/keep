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

private final class SourceCatalog: MusicCatalog {
    private(set) var lofiReads = 0
    private(set) var sourceReads = 0
    private(set) var streamReads = 0
    var fails = false
    func lofiTracks() async throws -> [MusicTrack] {
        lofiReads += 1
        if fails { throw MusicFailure.connection }
        return [track("lofi1"), track("lofi2")]
    }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] {
        sourceReads += 1
        return [track("saved1"), track("saved2")]
    }
    func streamURL(for track: MusicTrack) async throws -> URL {
        streamReads += 1
        guard let url = URL(string: "https://example.invalid/silent") else { throw MusicFailure.unavailable }
        return url
    }
    private func track(_ id: String) -> MusicTrack {
        MusicTrack(id: id, title: id, artist: "Silent fixture", permalink: nil)
    }
}

private final class SourcePlayback: MusicPlayback {
    var volume: Float = 0
    private var event: (@MainActor (MusicPlaybackEvent) -> Void)?
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {
        event = onEvent
        if autoplay { onEvent(.playing) }
    }
    func play() { event?(.playing) }
    func pause() {}
    func stop() { event = nil }
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
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]) else { throw CocoaError(.coderInvalidValue) }
            let reopened = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
            precondition(reopened.musicVolume == 0.27, "Cross-process volume reload")
            return
        }
        let suite = "keep.music-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        let playback = SilentPlayback()
        let model = MusicPlayerModel(catalog: SilentCatalog(), playback: playback, preferences: preferences)
        model.volume = 0.27
        expect(abs(playback.volume - 0.27) < 0.001, "Apply volume to Audius")
        let reopened = AppPreferences(persistence: persistence)
        expect(reopened.musicVolume == 0.27, "Restore exact last volume from disk")
        model.toggleMute()
        let muted = try persistence.load()
        expect(muted.musicVolume == 0, "Mute survives relaunch")
        model.toggleMute()
        expect(model.volume == 0.27, "Unmute restores the previous nonzero level")
        defaults.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--reload", suite]
        try child.run()
        child.waitUntilExit()
        expect(child.terminationStatus == 0, "A separate process restores the last volume")
        let restored = MusicPlayerModel(catalog: SilentCatalog(), playback: SilentPlayback(), preferences: reopened)
        expect(restored.volume == 0.27 && restored.state == .idle && !restored.wantsPlayback, "Relaunch restores volume without autoplay")
        model.shutdown(); restored.shutdown()

        // Old selections decode without retaining a provider abstraction or discarding other preferences.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.snapshot)) as? [String: Any] ?? [:]
        legacy["musicProvider"] = "appleMusic"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let migratedSelection = AppPreferences(persistence: persistence)
        expect(migratedSelection.canEdit && migratedSelection.musicVolume == 0.27, "Retired music selections cannot block saved preferences")
        migratedSelection.musicVolume = 0.29
        guard let rewrittenBytes = defaults.data(forKey: persistence.key),
              let rewritten = try JSONSerialization.jsonObject(with: rewrittenBytes) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        expect(rewritten["musicProvider"] == nil, "Saving discards the retired selection field")
        var portable = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PortableSettings(preferences.snapshot))) as? [String: Any] ?? [:]
        portable["musicProvider"] = "appleMusic"
        let restoredSettings = try JSONDecoder().decode(PortableSettings.self, from: JSONSerialization.data(withJSONObject: portable))
        expect(restoredSettings.applying(to: SettingsArchive()) == preferences.snapshot, "Older backups retain all supported settings while ignoring the removed selection")
        // Retired materials migrate without losing unrelated settings or accepting corrupt values.
        let beforeMigration = preferences.snapshot
        guard var legacyMaterial = try JSONSerialization.jsonObject(with: JSONEncoder().encode(beforeMigration)) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        legacyMaterial["glassStyle"] = "liquid"
        defaults.set(try JSONSerialization.data(withJSONObject: legacyMaterial), forKey: persistence.key)
        let frosted = AppPreferences(persistence: persistence)
        expect(frosted.canEdit && frosted.snapshot == beforeMigration, "Liquid Glass preferences migrate to frosted without losing other settings")
        frosted.glassiness = 0.73
        let savedFrosted = try persistence.load()
        expect(savedFrosted.glassStyle == .frosted && savedFrosted.glassiness == 0.73,
               "Migrated material and adjusted glassiness survive reload")
        guard let savedBytes = defaults.data(forKey: persistence.key),
              let savedMaterial = try JSONSerialization.jsonObject(with: savedBytes) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        expect(savedMaterial["glassStyle"] as? String == "frosted", "Saving rewrites the retired material using the compatible frosted value")
        legacyMaterial["glassStyle"] = "unknown-material"
        let invalidMaterial = try JSONSerialization.data(withJSONObject: legacyMaterial)
        defaults.set(invalidMaterial, forKey: persistence.key)
        let protectedMaterial = AppPreferences(persistence: persistence)
        protectedMaterial.glassiness = 0.2
        expect(!protectedMaterial.canEdit && defaults.data(forKey: persistence.key) == invalidMaterial,
               "Unknown material still protects the original archive from edits")

        // Existing preference archives omit the optional volume field.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.snapshot)) as? [String: Any] ?? [:]
        old.removeValue(forKey: "musicVolume")
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: persistence.key)
        let migrated = AppPreferences(persistence: persistence)
        expect(migrated.canEdit && migrated.musicVolume == 0.5, "Older archives load with safe volume defaults")
        old["musicVolume"] = 1.5
        let invalid = try JSONSerialization.data(withJSONObject: old)
        defaults.set(invalid, forKey: persistence.key)
        let blocked = AppPreferences(persistence: persistence)
        blocked.musicVolume = 0.2
        expect(!blocked.canEdit && defaults.data(forKey: persistence.key) == invalid, "Invalid volume blocks edits without overwriting preferences")
        try await sourceSelectionChecks()
        print("Passed \(checks) Audius music/preferences/legacy-backup checks (silent fixtures)")
    }

    private static func sourceSelectionChecks() async throws {
        let suite = "keep.sources-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite),
              let url = URL(string: "https://audius.co/fixture/playlist/focus") else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        let catalog = SourceCatalog()
        let model = MusicPlayerModel(catalog: catalog, playback: SourcePlayback(), preferences: preferences)
        var songIDs: [String] = []
        model.onTrackChange = { id in if let id { songIDs.append(id) } }
        model.playAudiusSource(nil)
        try await waitUntil { model.track?.id == "lofi1" && model.state == .playing }
        expect(preferences.snapshot.channels.isEmpty && model.wantsPlayback, "All Lofi plays before any sources are saved")
        let playlist = MusicChannel(resourceID: "playlist1", name: "Focus", kind: .playlist, url: url)
        preferences.saveChannel(playlist)
        model.playAudiusSource(playlist)
        try await waitUntil { model.track?.id == "saved1" && model.state == .playing }
        expect(model.selectedChannel == playlist && preferences.selectedChannel == playlist, "Saved-row Play captures and persists its source")
        model.next()
        try await waitUntil { model.track?.id == "saved2" && model.state == .playing }
        expect(model.selectedChannel == playlist, "Next stays inside the chosen playlist")
        expect(songIDs == ["lofi1", "saved1", "saved2"], "App-owned identity callback follows real selections once")
        model.playAudiusSource(nil)
        try await waitUntil { model.track?.id == "lofi1" && model.state == .playing }
        expect(model.selectedChannel == nil && preferences.selectedChannel == nil && model.wantsPlayback, "All Lofi leaves a playlist and starts discovery")
        expect(catalog.lofiReads == 2 && catalog.sourceReads == 1, "Leaving a playlist discards its queue and loads the lofi catalog")
        let reads = catalog.streamReads
        model.playAudiusSource(nil)
        expect(catalog.streamReads == reads && model.track?.id == "lofi1", "Selecting an already-playing source does not restart it")
        expect(songIDs.last == "lofi1" && songIDs.count == 4, "Repeated selection emits no duplicate song event")
        model.next()
        try await waitUntil { model.track?.id == "lofi2" && model.state == .playing }
        expect(model.selectedChannel == nil, "Next uses the lofi queue after leaving a playlist")
        model.togglePlayback()
        model.playAudiusSource(nil)
        expect(model.wantsPlayback && model.track?.id == "lofi2", "Selecting a paused source resumes without resetting its track")
        expect(songIDs.count == 5, "Pause/resume keeps the same song identity")
        let reopened = AppPreferences(persistence: persistence)
        expect(reopened.selectedChannel == nil && reopened.snapshot.channels == [playlist], "All Lofi selection survives reload without changing saved playlists")
        model.shutdown()
        model.selectChannel(nil)
        catalog.fails = true
        model.playAudiusSource(nil)
        try await waitUntil { model.state == .failed(.connection) }
        catalog.fails = false
        model.playAudiusSource(nil)
        try await waitUntil { model.track?.id == "lofi1" }
        expect(model.wantsPlayback, "Selecting All Lofi retries a failed source")
        model.shutdown()
    }

}
