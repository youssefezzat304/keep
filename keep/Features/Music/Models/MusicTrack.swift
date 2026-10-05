import Foundation

struct MusicTrack: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let permalink: URL?
}

enum MusicFailure: Error, Equatable {
    case connection, unavailable, noTracks, rateLimited

    var message: String {
        switch self {
        case .connection: "Couldn’t connect to Audius. Check your connection and retry."
        case .unavailable: "This track couldn’t play. Try another track or retry."
        case .noTracks: "No playable lofi tracks found. Try again in a moment."
        case .rateLimited: "Audius is busy. Wait a moment and retry."
        }
    }
}

enum MusicPlaybackState: Equatable {
    case idle, loading, playing, paused
    case failed(MusicFailure)
}
