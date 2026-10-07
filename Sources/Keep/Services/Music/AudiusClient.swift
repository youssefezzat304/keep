import Foundation

@MainActor
protocol MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack]
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack]
    func streamURL(for track: MusicTrack) async throws -> URL
}

extension MusicCatalog {
    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] { throw MusicFailure.unavailable }
}

/// Public read-only API. Signed stream URLs are resolved on demand, never persisted.
struct AudiusClient: MusicCatalog {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func lofiTracks() async throws -> [MusicTrack] {
        let data = try await request("tracks/search", query: [
            URLQueryItem(name: "query", value: "lofi"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "includePurchaseable", value: "false")
        ])
        return try decodeTracks(data)
    }

    func tracks(for channel: MusicChannel) async throws -> [MusicTrack] {
        guard channel.isValid else { throw MusicFailure.unavailable }
        let path = channel.kind == .artist ? "users/\(channel.resourceID)/tracks" : "playlists/\(channel.resourceID)/tracks"
        return try decodeTracks(await request(path, query: []))
    }

    func resolveChannel(_ text: String) async throws -> MusicChannel {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              MusicChannel.isAudiusURL(url) else { throw ChannelFailure.invalidURL }
        let data = try await request("resolve", query: [URLQueryItem(name: "url", value: url.absoluteString)])
        let response = try JSONDecoder().decode(ResolvedResponse.self, from: data)
        guard let resource = response.resources.first, MusicChannel.validID(resource.id) else { throw ChannelFailure.unsupported }
        let channel: MusicChannel
        if let name = resource.playlistName, resource.isDelete != true, resource.isPrivate != true {
            channel = MusicChannel(resourceID: resource.id, name: name, kind: .playlist, url: url)
        } else if let name = resource.name, resource.handle != nil {
            channel = MusicChannel(resourceID: resource.id, name: name, kind: .artist, url: url)
        } else { throw ChannelFailure.unsupported }
        guard channel.isValid else { throw ChannelFailure.unsupported }
        return channel
    }

    private func decodeTracks(_ data: Data) throws -> [MusicTrack] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        var seen = Set<String>()
        return response.data.compactMap { track in
            guard track.isAvailable == true, track.isStreamGated == false,
                  track.access?.stream == true, !track.isDelete, !track.isUnlisted,
                  !track.id.isEmpty, track.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
                  !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(track.id).inserted else { return nil }
            let link: URL?
            if let path = track.permalink, path.hasPrefix("/"), !path.hasPrefix("//"),
               var parts = URLComponents(string: "https://audius.co") {
                parts.path = path
                link = parts.url
            } else { link = nil }
            let artist: MusicChannel?
            if let id = track.user.id, let handle = track.user.handle,
               MusicChannel.validID(id), !handle.isEmpty,
               var parts = URLComponents(string: "https://audius.co") {
                parts.path = "/" + handle
                if let url = parts.url { artist = MusicChannel(resourceID: id, name: track.user.name, kind: .artist, url: url) }
                else { artist = nil }
            } else { artist = nil }
            return MusicTrack(id: track.id, title: track.title, artist: track.user.name, permalink: link,
                              artworkURL: track.artwork?.url, artistChannel: artist)
        }
    }

    func streamURL(for track: MusicTrack) async throws -> URL {
        guard !track.id.isEmpty, track.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw MusicFailure.unavailable
        }
        let data = try await request("tracks/\(track.id)/stream", query: [URLQueryItem(name: "no_redirect", value: "true")])
        let response = try JSONDecoder().decode(StreamResponse.self, from: data)
        guard let url = URL(string: response.data), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw MusicFailure.unavailable
        }
        return url
    }

    private func request(_ path: String, query: [URLQueryItem]) async throws -> Data {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.audius.co"
        parts.path = "/v1/" + path
        parts.queryItems = query + [URLQueryItem(name: "app_name", value: "Keep")]
        guard let url = parts.url else { throw MusicFailure.connection }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MusicFailure.connection }
        switch http.statusCode {
        case 200...299: return data
        case 403, 404: throw MusicFailure.unavailable
        case 429: throw MusicFailure.rateLimited
        default: throw MusicFailure.connection
        }
    }

    private struct SearchResponse: Decodable { let data: [TrackResponse] }
    private struct StreamResponse: Decodable { let data: String }
    private struct TrackResponse: Decodable {
        let id: String
        let title: String
        let user: Artist
        let permalink: String?
        let artwork: Artwork?
        let isAvailable: Bool?
        let isStreamGated: Bool?
        let access: Access?
        let isDelete: Bool
        let isUnlisted: Bool
        private enum CodingKeys: String, CodingKey {
            case id, title, user, permalink, access, artwork
            case isAvailable = "is_available", isStreamGated = "is_stream_gated"
            case isDelete = "is_delete", isUnlisted = "is_unlisted"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            user = try c.decode(Artist.self, forKey: .user)
            permalink = try c.decodeIfPresent(String.self, forKey: .permalink)
            artwork = try c.decodeIfPresent(Artwork.self, forKey: .artwork)
            access = try c.decodeIfPresent(Access.self, forKey: .access)
            isAvailable = try c.decodeIfPresent(Bool.self, forKey: .isAvailable)
            isStreamGated = try c.decodeIfPresent(Bool.self, forKey: .isStreamGated)
            isDelete = try c.decodeIfPresent(Bool.self, forKey: .isDelete) ?? false
            isUnlisted = try c.decodeIfPresent(Bool.self, forKey: .isUnlisted) ?? false
        }
    }
    private struct Artist: Decodable { let name: String; let id: String?; let handle: String? }
    private struct Artwork: Decodable {
        let large: String?; let medium: String?; let small: String?
        enum CodingKeys: String, CodingKey { case large = "1000x1000", medium = "480x480", small = "150x150" }
        var url: URL? {
            [large, medium, small].compactMap { value -> URL? in
                guard let value, let url = URL(string: value), url.scheme == "https",
                      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
                return url
            }.first
        }
    }
    private struct ResolvedResource: Decodable {
        let id: String; let name: String?; let handle: String?; let playlistName: String?
        let isDelete: Bool?; let isPrivate: Bool?
        enum CodingKeys: String, CodingKey {
            case id, name, handle
            case playlistName = "playlist_name", isDelete = "is_delete", isPrivate = "is_private"
        }
    }
    private struct ResolvedResponse: Decodable {
        let resources: [ResolvedResource]
        enum CodingKeys: String, CodingKey { case data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let single = try? c.decode(ResolvedResource.self, forKey: .data) { resources = [single] }
            else { resources = try c.decode([ResolvedResource].self, forKey: .data) }
        }
    }
    private struct Access: Decodable { let stream: Bool }
}
