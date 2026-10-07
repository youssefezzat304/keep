import Foundation
import Observation

nonisolated enum AppleMusicRepeat: String, CaseIterable, Sendable {
    case off, all, one
    var next: Self { switch self { case .off: .all; case .all: .one; case .one: .off } }
}

/// Runtime Music object IDs, never persisted or constructed from search text.
nonisolated struct AppleMusicItem: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Hashable, Sendable { case songs, playlists }
    let nativeID: Int32
    let kind: Kind
    let title: String
    let artist: String
    var playlistID: Int32? = nil
    var id: String { "\(kind.rawValue)-\(playlistID ?? 0)-\(nativeID)" }
}

nonisolated struct AppleMusicLibraryRequest: Equatable, Sendable {
    var kind: AppleMusicItem.Kind = .songs
    var query = ""
    var playlist: AppleMusicItem? = nil
    var offset = 0
    static let pageSize = 50
}

nonisolated struct AppleMusicLibraryPage: Sendable {
    let items: [AppleMusicItem]
    let hasMore: Bool
}

@Observable final class AppleMusicLibraryModel {
    enum State: Equatable { case idle, loading, ready, failed(MusicFailure) }
    private(set) var state: State = .idle
    private(set) var items: [AppleMusicItem] = []
    private(set) var hasMore = false
    @ObservationIgnored private let controller: any AppleMusicControlling
    @ObservationIgnored private let launch: @MainActor () async throws -> Void
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshID = 0

    init(controller: any AppleMusicControlling, launch: @escaping @MainActor () async throws -> Void) {
        self.controller = controller
        self.launch = launch
    }

    /// The sheet owns its task; search/selection changes cancel and fence older replies.
    func load(_ request: AppleMusicLibraryRequest, append: Bool = false, refreshID: Int = 0) async {
        generation = UUID()
        let token = generation
        state = .loading
        if !append { items = []; hasMore = false }
        do {
            if self.refreshID != refreshID {
                await controller.invalidateLibraryCache()
                try Task.checkCancellation()
                guard generation == token else { return }
                self.refreshID = refreshID
            }
            try await launch()
            try Task.checkCancellation()
            let page = try await controller.library(request)
            try Task.checkCancellation()
            guard generation == token else { return }
            var ids = Set(append ? items.map(\.id) : [])
            let unique = page.items.filter { ids.insert($0.id).inserted }
            items = append ? items + unique : unique
            hasMore = page.hasMore
            state = .ready
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            state = .failed(error as? MusicFailure == .appleMusicPermission ? .appleMusicPermission : .appleMusicLibrary)
        }
    }

    func cancel() { generation = UUID(); state = .idle }
}
