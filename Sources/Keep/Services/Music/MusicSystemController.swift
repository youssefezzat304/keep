import Foundation
import MediaPlayer

nonisolated enum MusicRemoteAction: Sendable { case play, pause, toggle, next, previous }

struct MusicSystemSnapshot: Equatable {
    let provider: MusicProvider
    let track: MusicTrack?
    let state: MusicPlaybackState
    let wantsPlayback: Bool
    let canSkip: Bool
    var ownsRemoteControls: Bool {
        provider == .audius && track != nil && (wantsPlayback || state == .paused || state == .playing || state == .loading)
    }
}

@MainActor protocol MusicSystemControlling: AnyObject {
    func connect(command: @escaping (MusicRemoteAction) -> Bool, outputChanged: @escaping () -> Void)
    func update(_ snapshot: MusicSystemSnapshot)
    func shutdown()
}

@MainActor protocol MusicRemoteControlling: AnyObject {
    func activate(command: @escaping @Sendable (MusicRemoteAction) -> Void)
    func update(_ snapshot: MusicSystemSnapshot)
    func deactivate()
}

/// One app-owned bridge. Music.app owns its own Now Playing integration when selected.
final class MusicSystemController: MusicSystemControlling {
    private let remote: any MusicRemoteControlling
    private let output: any AudioOutputObserving
    private var snapshot: MusicSystemSnapshot?
    private var command: ((MusicRemoteAction) -> Bool)?
    private var outputChanged: (() -> Void)?
    private var generation = UUID()
    private var outputGeneration = UUID()
    private var monitorsOutput = false
    private var ownsRemote = false

    convenience init() { self.init(remote: NativeMusicRemoteControls(), output: AudioOutputMonitor()) }
    init(remote: any MusicRemoteControlling, output: any AudioOutputObserving) {
        self.remote = remote; self.output = output
    }
    func connect(command: @escaping (MusicRemoteAction) -> Bool, outputChanged: @escaping () -> Void) {
        self.command = command; self.outputChanged = outputChanged
    }
    func update(_ next: MusicSystemSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
        if monitorsOutput != next.wantsPlayback {
            monitorsOutput = next.wantsPlayback; outputGeneration = UUID()
            if monitorsOutput {
                let token = outputGeneration
                output.start { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.monitorsOutput, self.outputGeneration == token else { return }
                        self.outputChanged?()
                    }
                }
            } else { output.stop() }
        }
        if next.ownsRemoteControls {
            if !ownsRemote {
                ownsRemote = true; generation = UUID()
                let token = generation
                remote.activate { [weak self] action in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.snapshot?.ownsRemoteControls == true else { return }
                        _ = self.command?(action)
                    }
                }
            }
            remote.update(next)
        } else if ownsRemote { releaseRemoteControls() }
    }
    private func releaseRemoteControls() {
        generation = UUID(); ownsRemote = false; remote.deactivate()
    }
    func shutdown() {
        if ownsRemote { releaseRemoteControls() }
        outputGeneration = UUID(); monitorsOutput = false; output.stop(); snapshot = nil
    }
}

/// Public MediaPlayer APIs receive media keys without a global keyboard/event tap.
private final class NativeMusicRemoteControls: MusicRemoteControlling {
    private let commands = MPRemoteCommandCenter.shared()
    private let nowPlaying = MPNowPlayingInfoCenter.default()
    private var targets: [(MPRemoteCommand, Any)] = []
    func activate(command: @escaping @Sendable (MusicRemoteAction) -> Void) {
        for (native, action) in [(commands.playCommand, MusicRemoteAction.play), (commands.pauseCommand, .pause),
                                (commands.stopCommand, .pause), (commands.togglePlayPauseCommand, .toggle),
                                (commands.nextTrackCommand, .next), (commands.previousTrackCommand, .previous)] {
            native.isEnabled = true
            let target = native.addTarget { _ in command(action); return .success }
            targets.append((native, target))
        }
    }
    func update(_ snapshot: MusicSystemSnapshot) {
        commands.nextTrackCommand.isEnabled = snapshot.canSkip
        commands.previousTrackCommand.isEnabled = snapshot.canSkip
        nowPlaying.nowPlayingInfo = [MPMediaItemPropertyTitle: snapshot.track?.title ?? "Keep",
            MPMediaItemPropertyArtist: snapshot.track?.artist ?? "",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.state == .playing ? 1.0 : 0.0]
        // macOS requires playbackState to route remote transport commands to the app.
        nowPlaying.playbackState = snapshot.state == .playing ? .playing : .paused
    }
    func deactivate() {
        for (native, target) in targets { native.removeTarget(target); native.isEnabled = false }
        targets.removeAll()
        nowPlaying.playbackState = .stopped; nowPlaying.nowPlayingInfo = nil
    }
}
