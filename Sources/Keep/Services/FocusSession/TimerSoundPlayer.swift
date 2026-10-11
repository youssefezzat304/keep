import AVFoundation
import Observation
import OSLog

/// App-owned audio: brief cues are queued so concurrent timers do not overlap.
@Observable
final class TimerSoundPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var errorMessage: String?
    private(set) var isPlaying = false
    @ObservationIgnored private var queue: [TimerSound] = []
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private let logger = Logger(subsystem: "com.youssef.keep", category: "Timer sounds")

    init(bundle: Bundle = .main) { self.bundle = bundle; super.init() }

    func play(_ sound: TimerSound) {
        queue.append(sound)
        guard playback == nil else { return }
        isPlaying = true
        let generation = generation
        playback = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !queue.isEmpty else { break }
                let sound = queue.removeFirst()
                do {
                    guard let url = Self.resourceURL(for: sound, in: bundle) else { throw CocoaError(.fileNoSuchFile) }
                    let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                    try Task.checkCancellation()
                    let audio = try AVAudioPlayer(data: data)
                    audio.delegate = self
                    guard audio.prepareToPlay(), audio.play() else { throw CocoaError(.fileReadUnknown) }
                    player = audio
                    errorMessage = nil
                    try await Task.sleep(for: .seconds(audio.duration + 0.05))
                    audio.stop()
                    player = nil
                } catch {
                    if Task.isCancelled { break }
                    reportFailure(error.localizedDescription)
                }
            }
            if self?.generation == generation {
                self?.playback = nil
                self?.isPlaying = false
            }
        }
    }

    static func resourceURL(for sound: TimerSound, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Sounds")
            ?? bundle.url(forResource: sound.rawValue, withExtension: "wav")
    }

    func stop() {
        generation = UUID()
        playback?.cancel()
        playback = nil
        player?.stop()
        player = nil
        queue.removeAll()
        isPlaying = false
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identity = ObjectIdentifier(player)
        let diagnostic = error?.localizedDescription ?? "Audio decoding failed"
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identity else { return }
            reportFailure(diagnostic)
        }
    }

    private func reportFailure(_ diagnostic: String) {
        logger.error("Timer sound failed: \(diagnostic, privacy: .public)")
        errorMessage = "The timer sound couldn’t play. Check your audio output, then try a sound preview again."
    }
}
