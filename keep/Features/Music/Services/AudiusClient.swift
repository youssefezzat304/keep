import Foundation

@MainActor
protocol MusicCatalog {
    func lofiTracks() async throws -> [MusicTrack]
    func streamURL(for track: MusicTrack) async throws -> URL
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
            return MusicTrack(id: track.id, title: track.title, artist: track.user.name, permalink: link)
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
        let isAvailable: Bool?
        let isStreamGated: Bool?
        let access: Access?
        let isDelete: Bool
        let isUnlisted: Bool
        private enum CodingKeys: String, CodingKey {
            case id, title, user, permalink, access
            case isAvailable = "is_available", isStreamGated = "is_stream_gated"
            case isDelete = "is_delete", isUnlisted = "is_unlisted"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            user = try c.decode(Artist.self, forKey: .user)
            permalink = try c.decodeIfPresent(String.self, forKey: .permalink)
            access = try c.decodeIfPresent(Access.self, forKey: .access)
            isAvailable = try c.decodeIfPresent(Bool.self, forKey: .isAvailable)
            isStreamGated = try c.decodeIfPresent(Bool.self, forKey: .isStreamGated)
            isDelete = try c.decodeIfPresent(Bool.self, forKey: .isDelete) ?? false
            isUnlisted = try c.decodeIfPresent(Bool.self, forKey: .isUnlisted) ?? false
        }
    }
    private struct Artist: Decodable { let name: String }
    private struct Access: Decodable { let stream: Bool }
}
