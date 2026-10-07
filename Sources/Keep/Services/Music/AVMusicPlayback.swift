import AVFoundation

enum MusicPlaybackEvent { case playing, waiting, ended, failed }

@MainActor
protocol MusicPlayback: AnyObject {
    var volume: Float { get set }
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void)
    func play()
    func pause()
    func stop()
}

/// Owns native playback and fences queued KVO/notification events from replaced items.
final class AVMusicPlayback: MusicPlayback {
    private let player = AVPlayer()
    private var observations: [NSKeyValueObservation] = []
    private var notifications: [NSObjectProtocol] = []
    private var generation = UUID()

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {
        stop()
        let token = generation
        let item = AVPlayerItem(url: url)
        observations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    onEvent(.failed)
                }
            },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    switch status {
                    case .playing: onEvent(.playing)
                    case .waitingToPlayAtSpecifiedRate: onEvent(.waiting)
                    default: break
                    }
                }
            }
        ]
        for (name, event) in [
            (AVPlayerItem.didPlayToEndTimeNotification, MusicPlaybackEvent.ended),
            (AVPlayerItem.failedToPlayToEndTimeNotification, MusicPlaybackEvent.failed)
        ] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    onEvent(event)
                }
            })
        }
        player.replaceCurrentItem(with: item)
        if autoplay { player.play() }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func stop() {
        generation = UUID()
        observations.removeAll()
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    deinit {
        notifications.forEach(NotificationCenter.default.removeObserver)
    }
}
