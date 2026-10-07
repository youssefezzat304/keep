import AppKit
import SwiftUI

@main enum WallpaperControlsChecks {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1; precondition(condition, message)
    }
    static func settle(_ library: WallpaperLibrary) async throws {
        for _ in 0..<300 {
            if !library.isLoading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        preconditionFailure("Wallpaper did not settle")
    }
    static func main() async throws {
        _ = NSApplication.shared
        let suite = "keep.wallpaper-controls.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        expect(SettingsArchive.rotationIntervals == [30, 60, 300, 900, 3600, 18000, 43200, 86400], "Keep old intervals and add all requested hours")
        expect(preferences.wallpaperRotationTrigger == .interval && preferences.loopWallpapers, "Legacy behavior remains timed and looping")
        expect(WallpaperIntervalChoice.customMinutes(hours: "12", minutes: "30") == 750, "Parse custom hours/minutes")
        expect(WallpaperIntervalChoice.customMinutes(hours: "999", minutes: "59") == 59999, "Bound maximum without overflow")
        for (hours, minutes) in [("0", "0"), ("1", "60"), ("-1", "30"), ("x", "1"), ("1000", "0"), ("99999999999999999999", "0")] {
            expect(WallpaperIntervalChoice.customMinutes(hours: hours, minutes: minutes) == nil, "Reject invalid or incomplete interval")
        }
        preferences.rotationSeconds = 86400
        expect(preferences.wallpaperIntervalChoice == .preset(86400), "Save 24-hour preset")
        preferences.wallpaperIntervalChoice = .custom
        preferences.customRotationMinutes = 750
        preferences.wallpaperRotationTrigger = .song
        let reopened = AppPreferences(persistence: persistence)
        expect(reopened.wallpaperIntervalChoice == .custom && reopened.customRotationMinutes == 750 && reopened.snapshot.effectiveRotationSeconds == 45000 && reopened.wallpaperRotationTrigger == .song, "Custom selection, duration and song trigger survive reload")
        preferences.customRotationMinutes = 0
        expect(preferences.customRotationMinutes == 750, "Invalid writes preserve saved preference")
        preferences.rotationSeconds = 18000
        expect(preferences.customRotationMinutes == nil && preferences.snapshot.effectiveRotationSeconds == 18000, "Preset clears custom mode")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SettingsArchive())) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "customRotationMinutes"); legacy.removeValue(forKey: "wallpaperRotationTrigger")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let old = AppPreferences(persistence: persistence)
        expect(old.canEdit && old.wallpaperIntervalChoice == .preset(60) && old.wallpaperRotationTrigger == .interval, "Older archives use previous defaults")
        legacy["customRotationMinutes"] = -1
        let corrupt = try JSONSerialization.data(withJSONObject: legacy)
        defaults.set(corrupt, forKey: persistence.key)
        let blocked = AppPreferences(persistence: persistence); blocked.customRotationMinutes = 60
        expect(!blocked.canEdit && defaults.data(forKey: persistence.key) == corrupt, "Corrupt preference bytes remain protected")

        var cycle = WallpaperCycle(); cycle.reset(count: 3, shuffled: false)
        expect(cycle.retreat() == 2 && cycle.advance(loop: true, shuffled: false) == 0, "Previous wraps, and next reverses it")
        expect(cycle.advance(loop: false, shuffled: false) == 1 && cycle.retreat() == 0, "Previous follows the current order")
        cycle.reset(count: 0, shuffled: true)
        expect(cycle.retreat() == nil, "Empty folder cannot go backwards")
        cycle.reset(count: 6, shuffled: true)
        let initial = cycle.current
        _ = cycle.advance(loop: true, shuffled: true)
        expect(cycle.retreat() == initial, "Previous reverses a shuffled step")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keep-wallpapers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<3 {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.coderInvalidValue) }
            context.setFillColor(red: index == 0 ? 1 : 0, green: index == 1 ? 1 : 0, blue: index == 2 ? 1 : 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
            try ArtworkWash.png(image).write(to: root.appendingPathComponent("\(index).png"))
        }
        let settings = AppPreferences(); settings.automaticallyRotate = false
        let library = WallpaperLibrary(); library.chooseFolder(root, preferences: settings)
        try await settle(library)
        let first = library.image?.tiffRepresentation
        library.next(); try await settle(library)
        let second = library.image?.tiffRepresentation
        expect(first != second && second != nil, "Next selects another wallpaper")
        settings.rotationSeconds = 43200
        library.configure(settings.snapshot.wallpaperConfiguration, preferences: settings)
        expect(!library.isLoading && library.image?.tiffRepresentation == second, "Changing timing retains the current wallpaper without decoding again")
        library.previous(); try await settle(library)
        expect(library.image?.tiffRepresentation == first, "Previous restores the preceding wallpaper")
        settings.wallpaperRotationTrigger = .song; settings.automaticallyRotate = true
        library.configure(settings.snapshot.wallpaperConfiguration, preferences: settings)
        library.songChanged(provider: .audius, trackID: "one")
        expect(!library.isLoading && library.image?.tiffRepresentation == first, "First track establishes baseline without jumping")
        library.songChanged(provider: .audius, trackID: "two"); try await settle(library)
        expect(library.image?.tiffRepresentation == second, "A different song advances once")
        library.songChanged(provider: .audius, trackID: nil)
        library.songChanged(provider: .audius, trackID: "two")
        expect(!library.isLoading && library.image?.tiffRepresentation == second, "Nil reads and repeated identity never double-advance")
        library.songChanged(provider: .appleMusic, trackID: "apple-one")
        expect(!library.isLoading, "Switching providers establishes a new baseline")
        library.songChanged(provider: .appleMusic, trackID: "apple-two"); try await settle(library)
        expect(library.image?.tiffRepresentation != second, "Apple Music song changes use the same rotation")
        settings.loopWallpapers = false; library.configure(settings.snapshot.wallpaperConfiguration, preferences: settings)
        library.songChanged(provider: .appleMusic, trackID: "apple-three")
        expect(library.rotationFinished && !library.isLoading, "Song rotation honors Loop off at the final wallpaper")
        library.previous(); try await settle(library)
        expect(!library.rotationFinished && library.image?.tiffRepresentation == second, "Manual navigation restarts a finished cycle")
        settings.automaticallyRotate = false; library.configure(settings.snapshot.wallpaperConfiguration, preferences: settings)
        library.songChanged(provider: .appleMusic, trackID: "apple-four")
        expect(!library.isLoading && library.image?.tiffRepresentation == second, "Automatic off suppresses song rotation")
        settings.automaticallyRotate = true; settings.wallpaperRotationTrigger = .interval
        var fast = settings.snapshot.wallpaperConfiguration
        fast = WallpaperConfiguration(source: fast.source, bookmark: fast.bookmark, order: fast.order, seconds: 1, automatic: true, loop: true)
        library.configure(fast, preferences: settings)
        try await Task.sleep(for: .milliseconds(1200)); try await settle(library)
        expect(library.image?.tiffRepresentation != second, "Timed rotation still advances through its single task")
        library.shutdown()
        try shortcutChecks()
        print("Passed \(checks) wallpaper control checks")
    }

    static func shortcutChecks() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let other = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { window.close(); other.close() }
        let view = WallpaperShortcutView(); window.contentView = view
        var moves: [Int] = []; view.onMove = { moves.append($0) }
        func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false, target: NSWindow? = nil) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: (target ?? window).windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: repeatKey, keyCode: code) else { throw CocoaError(.coderInvalidValue) }
            return event
        }
        let left = try key(123), right = try key(124)
        expect(view.handle(right) != nil, "Inactive or unhovered card leaves arrows alone")
        view.enabled = true
        expect(view.handle(left) == nil && view.handle(right) == nil && moves == [-1, 1], "Left/right route previous/next")
        expect(view.handle(try key(124, modifiers: .command)) != nil, "Modified shortcuts retain native behavior")
        expect(view.handle(try key(124, repeatKey: true)) == nil && moves == [-1, 1], "Held arrows are consumed silently without flooding image loads")
        expect(view.handle(try key(124, target: other)) != nil, "Other windows keep independent shortcut scope")
        expect(view.handle(try key(125)) != nil, "Up/down remain available for scrolling")
        let editor = NSTextView(); view.addSubview(editor); window.makeFirstResponder(editor)
        expect(view.handle(left) != nil, "Text editing retains arrow navigation")
        window.makeFirstResponder(nil)
        expect(view.filterEvent(right) == nil, "Native callback preserves consumption instead of restoring the event through optional coalescing")
        NSApplication.shared.sendEvent(right)
        expect(moves == [-1, 1, 1, 1], "Installed native monitor dispatches the shortcut")
        view.enabled = false
        expect(view.handle(right) != nil, "Hidden tabs disable shortcuts immediately")
        expect(view.filterEvent(right) === right, "Native callback preserves unhandled events")
        view.detach(); window.contentView = nil
    }
}
