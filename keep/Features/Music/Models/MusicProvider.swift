import Foundation

enum MusicProvider: String, Codable, CaseIterable, Identifiable {
    case audius, appleMusic
    var id: String { rawValue }
    var title: String { self == .audius ? "Audius" : "Apple Music" }
}

nonisolated struct AppleMusicSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable { case playing, paused, stopped }
    let state: State
    let title: String?
    let artist: String?
}

nonisolated enum AppleMusicCommand: Equatable, Sendable {
    case play, pause, next, previous, volume(Int), status
}

protocol AppleMusicControlling: Sendable {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot
}
