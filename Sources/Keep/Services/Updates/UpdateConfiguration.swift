import Foundation

struct UpdateConfiguration {
    let feedURL: URL?
    let publicKey: String?
    let version: String
    let build: String
    let isDevelopmentBuild: Bool

    init(bundle: Bundle = .main, isDevelopmentBuild: Bool = Self.developmentBuild) {
        self.init(info: bundle.infoDictionary ?? [:], isDevelopmentBuild: isDevelopmentBuild)
    }

    init(info: [String: Any], isDevelopmentBuild: Bool) {
        feedURL = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        publicKey = info["SUPublicEDKey"] as? String
        version = info["CFBundleShortVersionString"] as? String ?? "Development"
        build = info["CFBundleVersion"] as? String ?? "—"
        self.isDevelopmentBuild = isDevelopmentBuild
    }

    var isValid: Bool {
        guard let feedURL, feedURL.scheme == "https", let host = feedURL.host, !host.isEmpty,
              feedURL.user == nil, feedURL.password == nil, feedURL.fragment == nil,
              let publicKey, Data(base64Encoded: publicKey)?.count == 32,
              version != "Development", !version.isEmpty, build != "—", !build.isEmpty else { return false }
        return true
    }

    static var developmentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
