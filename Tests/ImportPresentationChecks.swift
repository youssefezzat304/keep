import AppKit
import SwiftUI

@main enum ImportPresentationChecks {
    static func main() {
        let app = NSApplication.shared
        let delegate = ImportWindows(); app.delegate = delegate
        app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor private final class ImportWindows: NSObject, NSApplicationDelegate {
    var checks = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { preconditionFailure("Import presentation failed: \(error)") }
            NSApp.terminate(nil)
        }
    }
    func run() async throws {
        let suite = "keep.import.presentation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
            catch { preconditionFailure("Couldn’t clean presentation fixtures: \(error)") }
        }
        let gate = BackupRestoreGate(), transaction = BackupRestoreTransaction(defaults: defaults, domain: suite, root: root)
        let habits = HabitStore(), preferences = AppPreferences(), tasks = DailyTaskStore()
        let workspace = WorkspaceModel(habits: habits)
        defer { workspace.shutdown() }
        let capture = SnapshotCapture(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, gate: gate)
        let importer = ImportCoordinator(capture: capture, gate: gate, transaction: transaction)
        let exporter = ExportModel(capture: capture); exporter.data = .all
        let output = URL(fileURLWithPath: "/tmp/keep-import-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (name, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
                try await render(KeepScrollView {
                    VStack(spacing: 24) { ExportSettingsView(model: exporter); ImportSettingsView(model: importer) }
                        .padding(32).frame(maxWidth: 900).frame(maxWidth: .infinity)
                }.background(KeepTheme.paper).keepAppearance(appearance), size: size, to: output.appendingPathComponent("transfers-\(name)-\(appearance.rawValue).png"))
            }
        }
        let first = try habits.add(name: "A reading habit with a longer descriptive title", icon: .book, startDay: "2026-10-01", endDay: nil, goal: .checkIn)
        var data = try KeepDataPayload(capture.capture(.backup))
        data.habits.habits = [Habit(id: UUID(), name: first.name, icon: .book, startDay: first.startDay, endDay: nil, goal: .amount(target: 30, unit: .minutes))]
        data.tasks.days["2027-01-01"] = [FocusTask(title: "A long imported task name that wraps naturally in the review summary", estimateMinutes: 60)]
        data.weeklyFocusGoalMinutes = 150
        let disk = transaction.disk
        let url = root.appendingPathComponent("Keep-All-with-a-long-archive-filename.keepdata")
        try await disk.write(try await disk.encode(KeepDataEnvelope(data, date: .now, appVersion: "checks")), to: url)
        importer.open(url); try await settle(importer)
        precondition(importer.review?.issues.contains { $0.requiresChoice } == true); checks += 1
        for appearance in [AppAppearance.light, .dark] {
            try await render(ImportReviewView(model: importer).keepAppearance(appearance), size: NSSize(width: 552, height: 540), to: output.appendingPathComponent("review-conflicts-\(appearance.rawValue).png"))
        }
        importer.open(url); try await settle(importer)
        importer.resolve("name/habit/" + (data.habits.habits.first?.id.uuidString ?? ""), .both)
        try await settle(importer)
        for appearance in [AppAppearance.light, .dark] {
            try await render(ImportReviewView(model: importer).keepAppearance(appearance), size: NSSize(width: 552, height: 540), to: output.appendingPathComponent("review-rename-\(appearance.rawValue).png"))
        }
        let corrupt = root.appendingPathComponent("invalid.keepdata")
        try await disk.write(Data("bad".utf8), to: corrupt)
        importer.open(corrupt); try await settle(importer)
        precondition(importer.phase == .failed); checks += 1
        for appearance in [AppAppearance.light, .dark] {
            try await render(ImportReviewView(model: importer).keepAppearance(appearance), size: NSSize(width: 552, height: 540), to: output.appendingPathComponent("review-error-\(appearance.rawValue).png"))
        }
        if ProcessInfo.processInfo.environment["KEEP_IMPORT_INTERACTIVE"] == "1" {
            importer.cancel()
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 680, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Keep — isolated Import UI"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: KeepScrollView {
                VStack(spacing: 24) { ExportSettingsView(model: exporter); ImportSettingsView(model: importer) }.padding(24)
            }.background(KeepTheme.paper).keepAppearance(.light))
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            FileHandle.standardOutput.write(Data("Interactive fixture ready. Input archive: \(url.path)\n".utf8))
            let deadline = ContinuousClock.now + .seconds(110)
            while window.isVisible && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(250)) }
            window.close()
        }
        print("Passed \(checks) native import presentation checks; captures in \(output.path)")
    }
    func settle(_ model: ImportCoordinator) async throws {
        for _ in 0..<300 { if !model.phase.busy { return }; try await Task.sleep(for: .milliseconds(10)) }
        throw ImportFailure.unavailable
    }
    func render<V: View>(_ view: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view); window.contentView = host
        window.setContentSize(size); host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded()
        precondition(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1); checks += 1
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.orderOut(nil)
        // Replacing a standalone host must not dismiss/cancel the app-owned review fixture.
        // Keep these hidden hosts alive until their isolated process exits.
        retained.append(window)
    }
    var retained: [NSWindow] = []
}
