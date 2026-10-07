import AppKit
import Foundation

private final class TestRemote: MusicRemoteControlling {
    var handler: (@Sendable (MusicRemoteAction) -> Void)?
    var activations = 0, releases = 0
    var snapshots: [MusicSystemSnapshot] = []
    func activate(command: @escaping @Sendable (MusicRemoteAction) -> Void) { activations += 1; handler = command }
    func update(_ snapshot: MusicSystemSnapshot) { snapshots.append(snapshot) }
    func deactivate() { releases += 1; handler = nil }
}
nonisolated private final class TestOutput: AudioOutputObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?
    private var starts = 0, stops = 0
    var counts: (Int, Int) { lock.withLock { (starts, stops) } }
    var handler: (@Sendable () -> Void)? { lock.withLock { callback } }
    func start(changed: @escaping @Sendable () -> Void) { lock.withLock { starts += 1; callback = changed } }
    func stop() { lock.withLock { stops += 1; callback = nil } }
}
private struct TestCatalog: MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack] { [fixture("one"), fixture("two"), fixture("three")] }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { try await lofiTracks() }
    func streamURL(for track: MusicTrack) async throws -> URL {
        guard let url = URL(string: "https://example.invalid/silent") else { throw MusicFailure.unavailable }
        return url
    }
    private func fixture(_ id: String) -> MusicTrack { MusicTrack(id: id, title: id, artist: "Silent fixture", permalink: nil) }
}
private final class DeferredCatalog: MusicCatalog {
    var continuation: CheckedContinuation<[MusicTrack], Never>?
    func lofiTracks() async throws -> [MusicTrack] { await withCheckedContinuation { continuation = $0 } }
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { try await lofiTracks() }
    func streamURL(for track: MusicTrack) async throws -> URL { throw MusicFailure.unavailable }
    func finish() {
        continuation?.resume(returning: [MusicTrack(id: "late", title: "Late song", artist: "Fixture", permalink: nil)])
        continuation = nil
    }
}
private final class TestPlayback: MusicPlayback {
    var volume: Float = 0
    var pauses = 0, plays = 0
    var event: (@MainActor (MusicPlaybackEvent) -> Void)?
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {
        event = onEvent; if autoplay { onEvent(.playing) }
    }
    func play() { plays += 1; event?(.playing) }
    func pause() { pauses += 1 }
    func stop() {}
}
private actor TestApple: AppleMusicControlling {
    var commands: [AppleMusicCommand] = []
    private var playing = false
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        commands.append(command)
        if command == .play { playing = true }
        if command == .pause { playing = false }
        return AppleMusicSnapshot(state: playing ? .playing : .paused, title: "Native song", artist: "Silent fixture", trackID: "native")
    }
}

@main enum SystemMusicChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func drain() async throws { try await Task.sleep(for: .milliseconds(40)) }
    static func ready(_ player: MusicPlayerModel) async throws {
        for _ in 0..<100 {
            if player.state == .playing { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Silent playback did not settle")
    }
    static func main() async throws {
        _ = NSApplication.shared
        let remote = TestRemote(), output = TestOutput()
        let system = MusicSystemController(remote: remote, output: output)
        let preferences = AppPreferences()
        let playback = TestPlayback(), apple = TestApple()
        let player = MusicPlayerModel(catalog: TestCatalog(), playback: playback, preferences: preferences,
            appleMusic: apple, launchAppleMusic: {}, appleRefreshInterval: .seconds(3600), isMusicRunning: { false }, systemControls: system)
        expect(remote.activations == 0 && output.counts.0 == 0, "Restoring an idle player never claims media keys or monitors output")
        expect(!player.handleRemoteAction(.play), "Unengaged player cannot autoplay through remote keys")
        player.togglePlayback(); try await ready(player)
        expect(remote.activations == 1 && output.counts.0 == 1, "Explicit Play activates exactly one remote target set and output observer")
        expect(remote.snapshots.last?.track?.id == "one" && remote.snapshots.last?.state == .playing, "Publish title and actual Playing state for macOS routing")
        expect(remote.snapshots.last?.canSkip == true, "Enable track keys for a populated queue")
        remote.handler?(.pause); try await drain()
        expect(player.state == .paused && !player.wantsPlayback, "F8/native Pause pauses Audius")
        expect(remote.releases == 0 && output.counts.1 == 1, "Paused track keeps resume controls but releases output observation")
        let pauses = playback.pauses
        remote.handler?(.pause); try await drain()
        expect(playback.pauses == pauses && player.state == .paused, "Repeated Pause is idempotent")
        remote.handler?(.play); try await ready(player)
        expect(playback.plays == 1 && remote.activations == 1, "Native Play resumes current item without duplicate targets")
        remote.handler?(.next); try await drain(); try await ready(player)
        expect(player.track?.id == "two", "F9/native Next advances once")
        remote.handler?(.previous); try await drain(); try await ready(player)
        expect(player.track?.id == "one", "F7/native Previous goes back once")
        let staleOutput = output.handler
        output.handler?(); try await drain()
        expect(player.state == .paused && !player.wantsPlayback, "Output device/source change pauses active playback")
        playback.event?(.playing)
        expect(player.state == .paused && !player.wantsPlayback, "Late native Playing cannot resume after a route change")
        playback.event?(.ended)
        expect(player.track?.id == "one", "Late Ended cannot skip after a route pause")
        remote.handler?(.toggle); try await ready(player)
        staleOutput?(); try await drain()
        expect(player.state == .playing && player.wantsPlayback, "Old output callback cannot pause a new playback generation")
        remote.handler?(.toggle); try await drain()
        expect(player.state == .paused, "Native Toggle handles both directions")
        let staleCommand = remote.handler
        player.selectProvider(.appleMusic)
        expect(remote.releases == 1 && remote.handler == nil, "Apple Music selection relinquishes Keep media keys to Music.app")
        staleCommand?(.next); try await drain()
        expect(player.track == nil && !player.wantsPlayback, "Queued media commands cannot cross provider changes")
        expect(await apple.commands.isEmpty, "Passive provider selection never launches or contacts Music")
        player.togglePlayback(); try await ready(player)
        expect(remote.activations == 1 && remote.handler == nil, "Native Music retains sole remote command ownership")
        let staleAppleOutput = output.handler
        output.handler?(); try await drain()
        expect(!player.wantsPlayback && player.state == .paused, "Keep pauses engaged Apple Music on output changes too")
        expect(await apple.commands.filter { $0 == .pause }.count == 1, "One route change sends one native Music pause")
        player.selectProvider(.audius); player.togglePlayback(); try await ready(player)
        expect(remote.activations == 2 && remote.snapshots.last?.provider == .audius, "Returning to Audius registers a fresh command generation")
        staleAppleOutput?(); try await drain()
        expect(player.wantsPlayback, "Stale native-provider observer cannot pause Audius")
        let shutdownCommand = remote.handler, shutdownOutput = output.handler
        player.shutdown()
        shutdownCommand?(.play); shutdownOutput?(); try await drain()
        expect(player.state == .idle && !player.wantsPlayback && remote.handler == nil, "Termination removes handlers and fences queued commands/routes")
        expect(remote.releases == 2 && output.handler == nil, "Shutdown releases the active native bridge")
        let pendingCatalog = DeferredCatalog(), pendingOutput = TestOutput(), pendingRemote = TestRemote()
        let pendingSystem = MusicSystemController(remote: pendingRemote, output: pendingOutput)
        let pendingPlayer = MusicPlayerModel(catalog: pendingCatalog, playback: TestPlayback(), preferences: preferences,
            appleMusic: TestApple(), launchAppleMusic: {}, isMusicRunning: { false }, systemControls: pendingSystem)
        pendingPlayer.togglePlayback(); try await drain()
        expect(pendingPlayer.state == .loading && pendingOutput.counts.0 == 1, "Monitor the route while a stream is still loading")
        pendingOutput.handler?(); try await drain()
        expect(pendingPlayer.state == .paused && !pendingPlayer.wantsPlayback, "Disconnect cancels pending playback before audio starts")
        pendingCatalog.finish(); try await drain()
        expect(pendingPlayer.track == nil && pendingPlayer.state == .paused, "Late catalog completion cannot play after a disconnect")
        expect(pendingRemote.activations == 0, "No media-key ownership is claimed for an unloaded track")
        pendingPlayer.shutdown()
        print("Passed \(checks) system music checks (silent fake transport/output; no media center or audio used)")
    }
}
