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
    var trackID: String? = nil
    var artwork: Data? = nil
    var position: Double = 0
    var duration: Double = 0
    var shuffled = false
    var repeatMode: AppleMusicRepeat = .off
}

nonisolated enum AppleMusicCommand: Equatable, Sendable {
    case play, pause, next, previous, volume(Int), status
    case playItem(AppleMusicItem), seek(Double), shuffle(Bool), repeatMode(AppleMusicRepeat)
}

protocol AppleMusicControlling: Sendable {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot
    func invalidateLibraryCache() async
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage
    func access(requestPermission: Bool) async -> AppleMusicAccess
}

extension AppleMusicControlling {
    func invalidateLibraryCache() async {}
    func access(requestPermission: Bool) async -> AppleMusicAccess { .notChecked }
    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage {
        throw MusicFailure.appleMusicConnection
    }
}
