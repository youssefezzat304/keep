import Foundation

protocol ExportFileWriting: Actor {
    func prepare(_ request: ExportRequest, snapshot: PersistentSnapshot) async throws -> ExportArtifact
    func save(_ artifact: ExportArtifact, to destination: URL) async throws
    func remove(_ artifact: ExportArtifact) async throws
}

/// Private staging, ZIP packaging and coordinated atomic saving never run on the UI actor.
actor ExportFiles: ExportFileWriting {
    let temporaryRoot: URL
    init(temporaryRoot: URL = FileManager.default.temporaryDirectory) { self.temporaryRoot = temporaryRoot }

    func prepare(_ request: ExportRequest, snapshot: PersistentSnapshot) throws -> ExportArtifact {
        let manager = FileManager.default
        let root = temporaryRoot.appendingPathComponent("Keep-Export-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let reports = try ExportReports.make(request, snapshot: snapshot)
            try Task.checkCancellation()
            let name = request.filename(calendar: snapshot.calendar)
            let output = root.appendingPathComponent(name)
            if request.data == .stats {
                let directory = root.appendingPathComponent("Reports", isDirectory: true)
                try manager.createDirectory(at: directory, withIntermediateDirectories: false)
                for report in reports {
                    try Task.checkCancellation()
                    try report.contents.write(to: directory.appendingPathComponent(report.filename), options: .atomic)
                }
                var coordinationError: NSError?
                var outcome: Result<Void, Error> = .failure(ExportFailure.saveFailed)
                NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinationError) { zippedURL in
                    // Foundation deletes this ZIP after the accessor. Own a copy before returning.
                    outcome = Result { try manager.copyItem(at: zippedURL, to: output) }
                }
                if let coordinationError { throw coordinationError }
                try outcome.get()
                try manager.removeItem(at: directory)
            } else {
                guard let report = reports.first else { throw ExportFailure.saveFailed }
                try report.contents.write(to: output, options: .atomic)
            }
            try Task.checkCancellation()
            return ExportArtifact(root: root, url: output, filename: name)
        } catch {
            try manager.removeItem(at: root)
            throw error
        }
    }

    func save(_ artifact: ExportArtifact, to destination: URL) throws {
        try Task.checkCancellation()
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        // NSSavePanel may already supply its scope; false alone does not mean access was denied.
        var coordinationError: NSError?
        var outcome: Result<Void, Error> = .failure(ExportFailure.saveFailed)
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
            outcome = Result {
                try Task.checkCancellation()
                try Data(contentsOf: artifact.url, options: .mappedIfSafe).write(to: url, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }

    func remove(_ artifact: ExportArtifact) throws {
        if FileManager.default.fileExists(atPath: artifact.root.path) { try FileManager.default.removeItem(at: artifact.root) }
    }
}
