import Foundation
import Network

@MainActor protocol BackupCloudStorage: AnyObject {
    var account: Data? { get }
    var versions: [BackupVersion] { get }
    var isOffline: Bool { get }
    var onChange: (() -> Void)? { get set }
    func accountMatches(_ archived: Data?) -> Bool
    func connect() async throws
    func submit(_ data: Data, envelope: BackupEnvelope) async throws -> URL
    func read(_ version: BackupVersion) async throws -> Data
    func remove(_ version: BackupVersion) async throws
}

extension BackupCloudStorage {
    func accountMatches(_ archived: Data?) -> Bool { account != nil && account == archived }
}

/// Apple defines identity equality on the opaque token, not on its archive representation.
nonisolated enum ICloudBackupIdentity {
    static func archive() throws -> Data? {
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    }
    static func matches(_ archived: Data?) -> Bool {
        matches(archived, token: FileManager.default.ubiquityIdentityToken)
    }
    static func matches(_ archived: Data?, token: (any NSObjectProtocol & NSCoding & NSCopying)?) -> Bool {
        guard let archived, let token else { return false }
        do {
            if try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) == archived { return true }
            let classes: [AnyClass] = [type(of: token as AnyObject), NSData.self, NSString.self, NSUUID.self,
                                      NSNumber.self, NSDictionary.self, NSArray.self, NSSet.self, NSURL.self, NSDate.self]
            let decoder = try NSKeyedUnarchiver(forReadingFrom: archived)
            decoder.requiresSecureCoding = false
            decoder.decodingFailurePolicy = .setErrorAndReturn
            let previous = decoder.decodeObject(of: classes, forKey: NSKeyedArchiveRootObjectKey)
            decoder.finishDecoding()
            if let error = decoder.error { throw error }
            return token.isEqual(previous)
        } catch {
            // Failure denies account-bound access; never log token bytes or identity details.
            let failure = error as NSError
            NSLog("Keep: iCloud backup identity comparison failed (%@ %ld).", failure.domain, failure.code)
            return false
        }
    }
}

/// Coordinators may block; their accessors execute on a dedicated actor rather than the UI thread.
actor ICloudBackupFiles {
    let manager = FileManager.default
    func container() throws -> URL {
        guard let url = manager.url(forUbiquityContainerIdentifier: "iCloud.com.youssef.keep") else { throw CocoaError(.ubiquitousFileUnavailable) }
        return url
    }
    private func checkAccount(_ expected: Data) throws {
        guard ICloudBackupIdentity.matches(expected) else { throw BackupFailure.accountChanged }
    }
    func write(_ data: Data, to url: URL, account: Data) throws {
        try checkAccount(account)
        var coordinationError: NSError?; var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            do {
                try checkAccount(account)
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if manager.fileExists(atPath: destination.path) {
                    guard try Data(contentsOf: destination) == data else { throw CocoaError(.fileWriteFileExists) }
                } else { try data.write(to: destination, options: .atomic) }
            } catch { failure = error }
        }
        if let error = coordinationError ?? failure as NSError? { throw error }
    }
    func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?; var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
            result = Result {
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                return try Data(contentsOf: source)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
    func download(_ url: URL) throws { try manager.startDownloadingUbiquitousItem(at: url) }
    func remove(_ url: URL, account: Data) throws {
        try checkAccount(account)
        var coordinationError: NSError?; var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { source in
            do { try checkAccount(account); try manager.removeItem(at: source) } catch { failure = error }
        }
        if let error = coordinationError ?? failure as NSError? { throw error }
    }
}

final class ICloudBackupStorage: BackupCloudStorage {
    private(set) var versions: [BackupVersion] = []
    private(set) var isOffline = false
    var onChange: (() -> Void)?
    var account: Data? {
        do { return try ICloudBackupIdentity.archive() }
        catch {
            let failure = error as NSError
            NSLog("Keep: iCloud backup identity unavailable (%@ %ld).", failure.domain, failure.code)
            return nil
        }
    }
    func accountMatches(_ archived: Data?) -> Bool { ICloudBackupIdentity.matches(archived) }
    private let files = ICloudBackupFiles()
    private let query = NSMetadataQuery()
    private var root: URL?
    private var epoch = UUID()
    private var observers: [NSObjectProtocol] = []
    private var monitor: NWPathMonitor?

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.epoch = UUID(); self.root = nil; self.query.stop(); self.versions = []
                self.onChange?()
            }
        })
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, Notification.Name.NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func connect() async throws {
        guard account != nil else { throw BackupFailure.unavailable }
        if monitor == nil {
            let pathMonitor = NWPathMonitor()
            pathMonitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor [weak self] in self?.isOffline = path.status == .unsatisfied; self?.onChange?() }
            }
            pathMonitor.start(queue: DispatchQueue(label: "keep.backup.network")); monitor = pathMonitor
        }
        guard root == nil else { return }
        let token = epoch
        let container = try await files.container()
        guard token == epoch, account != nil else { throw BackupFailure.accountChanged }
        root = container.appendingPathComponent("Documents/Backups", isDirectory: true)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K ENDSWITH '.keepbackup' AND %K BEGINSWITH %@", NSMetadataItemFSNameKey, NSMetadataItemPathKey, root?.path ?? "")
        guard query.start() else { root = nil; throw BackupFailure.unavailable }
    }

    private func refresh() {
        guard let root else { return }
        query.disableUpdates(); defer { query.enableUpdates() }
        versions = query.results.compactMap { object in
            guard let item = object as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
                  UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) != nil,
                  let date = BackupEnvelope.date(fromFilename: url.lastPathComponent) else { return nil }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let error = (item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError)
                ?? (item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError)
            return BackupVersion(url: url, createdAt: date, deviceID: url.deletingLastPathComponent().lastPathComponent,
                uploaded: (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) == true,
                uploading: (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool) == true,
                downloaded: status == NSMetadataUbiquitousItemDownloadingStatusCurrent || status == NSMetadataUbiquitousItemDownloadingStatusDownloaded,
                error: error?.localizedDescription)
        }.sorted { $0.createdAt > $1.createdAt }
        onChange?()
    }

    func submit(_ data: Data, envelope: BackupEnvelope) async throws -> URL {
        try await connect()
        guard let root, let account else { throw BackupFailure.unavailable }
        let token = epoch
        let url = root.appendingPathComponent(envelope.deviceID.uuidString, isDirectory: true).appendingPathComponent(envelope.filename)
        try await files.write(data, to: url, account: account)
        guard token == epoch else { throw BackupFailure.accountChanged }
        return url
    }
    func read(_ version: BackupVersion) async throws -> Data {
        try await connect()
        guard versions.contains(where: { $0.id == version.id }) else { throw BackupFailure.unavailable }
        let token = epoch
        if !version.downloaded {
            try await files.download(version.url)
            // Metadata events, rather than a coordinated read, tell us when a download finishes.
            for _ in 0..<120 {
                try Task.checkCancellation()
                guard token == epoch else { throw BackupFailure.accountChanged }
                if let item = versions.first(where: { $0.id == version.id }) {
                    if let error = item.error { throw NSError(domain: "KeepBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                    if item.downloaded { break }
                }
                try await Task.sleep(for: .seconds(1))
            }
            guard versions.first(where: { $0.id == version.id })?.downloaded == true else { throw BackupFailure.unavailable }
        }
        let data = try await files.read(version.url)
        guard token == epoch else { throw BackupFailure.accountChanged }
        return data
    }
    func remove(_ version: BackupVersion) async throws {
        guard versions.contains(where: { $0.id == version.id && $0.uploaded }) else { return }
        guard let account else { throw BackupFailure.unavailable }
        try await files.remove(version.url, account: account)
    }
}
