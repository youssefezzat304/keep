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

nonisolated enum MusicFailure: Error, Equatable {
    case connection, unavailable, noTracks, rateLimited, appleMusicPermission, appleMusicConnection, appleMusicLibrary

    var message: String {
        switch self {
        case .connection: "Couldn’t connect to Audius. Check your connection and retry."
        case .unavailable: "This track couldn’t play. Try another track or retry."
        case .noTracks: "No playable tracks found. Try again in a moment."
        case .rateLimited: "Audius is busy. Wait a moment and retry."
        case .appleMusicPermission: "Allow Keep to control Music in System Settings → Privacy & Security → Automation, then retry."
        case .appleMusicConnection: "Open Music, sign in if needed, and choose a song or playlist. Then retry here."
        case .appleMusicLibrary: "Couldn’t read your Music library. Open Music, let your library load, then retry here."
        }
    }
}

enum MusicPlaybackState: Equatable {
    case idle, loading, playing, paused
    case failed(MusicFailure)
}
