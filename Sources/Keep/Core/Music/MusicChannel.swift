import Foundation

nonisolated struct MusicChannel: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case artist, playlist }
    let resourceID: String
    let name: String
    let kind: Kind
    let url: URL
    var id: String { "\(kind.rawValue):\(resourceID)" }
    var subtitle: String { kind == .artist ? "Artist profile" : "Playlist" }
    var symbol: String { kind == .artist ? "person.crop.circle" : "music.note.list" }
    var isValid: Bool {
        Self.validID(resourceID) && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && Self.isAudiusURL(url)
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    static func isAudiusURL(_ url: URL) -> Bool {
        url.scheme == "https" && ["audius.co", "www.audius.co"].contains(url.host?.lowercased() ?? "")
        && url.user == nil && url.password == nil && !url.path.isEmpty && url.path != "/"
    }
}

enum ChannelFailure: Error {
    case invalidURL, unsupported
    var message: String {
        switch self {
        case .invalidURL: "Paste an https://audius.co artist or playlist link."
        case .unsupported: "That link isn’t an artist profile or playlist. Try another Audius link."
        }
    }
}
