import Foundation

struct MusicTrack: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let permalink: URL?
    let artworkURL: URL?
    let artistChannel: MusicChannel?

    init(id: String, title: String, artist: String, permalink: URL?, artworkURL: URL? = nil, artistChannel: MusicChannel? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.permalink = permalink
        self.artworkURL = artworkURL; self.artistChannel = artistChannel
    }
}

enum MusicFailure: Error, Equatable {
    case connection, unavailable, noTracks, rateLimited

    var message: String {
        switch self {
        case .connection: "Couldn’t connect to Audius. Check your connection and retry."
        case .unavailable: "This track couldn’t play. Try another track or retry."
        case .noTracks: "No playable tracks found. Try again in a moment."
        case .rateLimited: "Audius is busy. Wait a moment and retry."
        }
    }
}

enum MusicPlaybackState: Equatable {
    case idle, loading, playing, paused
    case failed(MusicFailure)
}
