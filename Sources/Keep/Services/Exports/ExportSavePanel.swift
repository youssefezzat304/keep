import AppKit
import UniformTypeIdentifiers

/// The caller owns and must stop the implicit scope of a returned native-panel URL.
protocol ExportSavePanel {
    func destination(filename: String, data: ExportData, window: NSWindow?) async throws -> URL?
    func cancel()
}

final class NativeExportSavePanel: ExportSavePanel {
    private var panel: NSSavePanel?
    func destination(filename: String, data: ExportData, window: NSWindow?) async throws -> URL? {
        guard let window else { throw ExportFailure.noWindow }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [data == .stats ? .zip : .commaSeparatedText]
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.title = "Export \(data.rawValue)"
        self.panel = panel
        defer { self.panel = nil }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
    func cancel() { panel?.cancel(nil) }
}
