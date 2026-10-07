import Foundation

/// Successful, read-only library data. All lifetimes use the original fetch time.
/// Kept inside the serial controller; the synchronous loader cannot race a Refresh.
nonisolated struct AppleMusicLibraryCache {
    struct Row: Sendable {
        let item: AppleMusicItem
        let album: String
        var accountedBytes: Int { 128 + item.title.utf8.count + item.artist.utf8.count + album.utf8.count }
    }
    private struct Collection: Hashable {
        let kind: AppleMusicItem.Kind
        let playlist: Int32?
        let locale: String
    }
    private struct Key: Hashable { let collection: Collection; let query: String; let offset: Int }
    private struct Page { let key: Key; let value: AppleMusicLibraryPage; let fetchedAt: Double; let bytes: Int }
    private struct Metadata { let collection: Collection; let rows: [Row]; let fetchedAt: Double }
    private var pages: [Page] = []
    private var metadata: Metadata?
    private var processID: Int32?
    private let clock: @Sendable () -> Double
    static let lifetime = 60.0
    static let pageLimit = 24
    static let itemLimit = 20_000
    static let byteLimit = 8 * 1024 * 1024
    var pageCount: Int { pages.count }
    var metadataCount: Int { metadata?.rows.count ?? 0 }

    init(clock: @escaping @Sendable () -> Double = {
        let elapsed = ContinuousClock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }) { self.clock = clock }
    private static let origin = ContinuousClock.now

    mutating func removeAll() { pages = []; metadata = nil }

    mutating func load(_ request: AppleMusicLibraryRequest, processID: Int32?, locale: String = Locale.current.identifier,
                       verifyAccess: () throws -> Void,
                       readPage: (AppleMusicLibraryRequest) throws -> AppleMusicLibraryPage,
                       readMetadata: (AppleMusicLibraryRequest) throws -> [Row]) throws -> AppleMusicLibraryPage {
        try Task.checkCancellation()
        guard (0...1_000_000).contains(request.offset) else { throw MusicFailure.appleMusicConnection }
        if self.processID != processID { removeAll(); self.processID = processID }
        // Cached content must never bypass the controller's real scoped access checks.
        do {
            try verifyAccess()
            try Task.checkCancellation()
            let now = clock()
            pages.removeAll { now - $0.fetchedAt >= Self.lifetime || now < $0.fetchedAt }
            if let metadata, now - metadata.fetchedAt >= Self.lifetime || now < metadata.fetchedAt { self.metadata = nil }
            var normalized = request
            normalized.query = String(request.query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            let kind = request.playlist == nil ? request.kind : .songs
            let collection = Collection(kind: kind, playlist: request.playlist?.nativeID, locale: locale)
            let key = Key(collection: collection, query: normalized.query, offset: request.offset)
            if let position = pages.firstIndex(where: { $0.key == key }) {
                let page = pages.remove(at: position); pages.append(page); return page.value
            }
            let value: AppleMusicLibraryPage
            var fetchedMetadata: Metadata?
            var fetchedAt = now
            if normalized.query.isEmpty { value = try readPage(normalized) }
            else {
                let rows: [Row]
                if let metadata, metadata.collection == collection { rows = metadata.rows; fetchedAt = metadata.fetchedAt }
                else {
                    rows = try readMetadata(normalized)
                    try Task.checkCancellation()
                    let bytes = rows.reduce(0) { $0 + $1.accountedBytes }
                    if rows.count <= Self.itemLimit && bytes <= Self.byteLimit {
                        fetchedMetadata = Metadata(collection: collection, rows: rows, fetchedAt: fetchedAt)
                    } else { metadata = nil }
                }
                var result: [AppleMusicItem] = [], matched = 0, hasMore = false
                for row in rows {
                    try Task.checkCancellation()
                    guard [row.item.title, row.item.artist, row.album].contains(where: { $0.localizedStandardContains(normalized.query) }) else { continue }
                    if matched >= normalized.offset {
                        if result.count == AppleMusicLibraryRequest.pageSize { hasMore = true; break }
                        result.append(row.item)
                    }
                    matched += 1
                }
                value = AppleMusicLibraryPage(items: result, hasMore: hasMore)
            }
            try Task.checkCancellation()
            if clock() - fetchedAt < Self.lifetime {
                if let fetchedMetadata { metadata = fetchedMetadata }
                let bytes = value.items.reduce(0) { $0 + 128 + $1.title.utf8.count + $1.artist.utf8.count }
                if bytes <= Self.byteLimit {
                    pages.append(Page(key: key, value: value, fetchedAt: fetchedAt, bytes: bytes))
                    while pages.count > Self.pageLimit || pages.reduce(0, { $0 + $1.bytes }) > Self.byteLimit { pages.removeFirst() }
                }
            }
            return value
        } catch {
            if error as? MusicFailure == .appleMusicPermission { removeAll() }
            throw error
        }
    }
}
