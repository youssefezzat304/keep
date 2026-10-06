import AppKit
import Observation
import SwiftUI

@Observable private final class AppearanceReading {
    var scheme: ColorScheme?
}

private struct AppearanceProbe: View {
    @Environment(\.colorScheme) private var scheme
    let reading: AppearanceReading
    var body: some View {
        Text("Appearance")
            .onChange(of: scheme, initial: true) { _, value in reading.scheme = value }
    }
}

private struct AppearanceRoot: View {
    let preferences: AppPreferences
    let reading: AppearanceReading
    var body: some View { AppearanceProbe(reading: reading).keepAppearance(preferences.appearance) }
}

/// Native offscreen windows; changes affect this test process only, never macOS settings.
@main enum AppearanceChecks {
    private static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }
    static func settle() async throws { try await Task.sleep(for: .milliseconds(350)) }

    static func main() async throws {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        app.appearance = NSAppearance(named: .darkAqua)
        let system = SystemAppearance()
        let preferences = AppPreferences()
        let readings = [AppearanceReading(), AppearanceReading()]
        let windows = readings.map { reading in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AppearanceRoot(preferences: preferences, reading: reading))
            window.contentView?.layoutSubtreeIfNeeded()
            return window
        }
        defer { windows.forEach { $0.close() } }
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .light }, "Explicit Light overrides a dark Mac in every window")
        expect(system.colorScheme == .dark, "System appearance stays independent of window overrides")
        preferences.appearance = .system
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .dark }, "Light to System updates all SwiftUI content immediately")
        app.appearance = NSAppearance(named: .aqua)
        try await settle()
        expect(system.colorScheme == .light, "Observe the native system appearance changing")
        expect(readings.allSatisfy { $0.scheme == .light }, "System content follows a light Mac without reopening")
        preferences.appearance = .dark
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .dark }, "Explicit Dark overrides a light Mac")
        preferences.appearance = .system
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .light }, "Dark to System releases the dark override")
        app.appearance = NSAppearance(named: .darkAqua)
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .dark }, "System follows subsequent dark changes")
        preferences.appearance = .light
        try await settle()
        app.appearance = NSAppearance(named: .aqua)
        try await settle()
        app.appearance = NSAppearance(named: .darkAqua)
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .light }, "Native changes leave explicit Light intact")
        preferences.appearance = .system
        try await settle()
        expect(readings.allSatisfy { $0.scheme == .dark }, "Repeated Light to System transitions remain correct")
        print("Passed \(checks) native appearance checks")
    }
}
