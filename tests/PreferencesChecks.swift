import Foundation
import ImageIO
import UniformTypeIdentifiers

@main enum PreferencesChecks {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }

    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3 {
            guard let defaults = UserDefaults(suiteName: CommandLine.arguments[2]),
                  let url = URL(string: "https://audius.co/softloops") else { throw CocoaError(.coderInvalidValue) }
            let persistence = SettingsPersistence(defaults: defaults)
            if CommandLine.arguments[1] == "write" {
                let preferences = AppPreferences(persistence: persistence)
                preferences.appearance = .system; preferences.wallpaperSource = .audius
                preferences.glassStyle = .liquid; preferences.glassiness = 0.75
                let artist = MusicChannel(resourceID: "artist1", name: "Soft loops", kind: .artist, url: url)
                preferences.saveChannel(artist); preferences.selectChannel(artist)
                defaults.synchronize()
            } else {
                let archive = try persistence.load()
                expect(archive.appearance == .system && archive.wallpaperSource == .audius && archive.glassiness == 0.75, "Cross-process appearance/material preferences")
                expect(archive.channels.count == 1 && archive.selectedChannelID == "artist:artist1", "Cross-process saved and selected Audius channel")
            }
            return
        }
        let suite = "keep.preferences.checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        expect(preferences.canEdit && preferences.snapshot == SettingsArchive(), "Default settings preserve existing light/cozy appearance")
        expect(AppAppearance.light.colorScheme == .light && AppAppearance.dark.colorScheme == .dark && AppAppearance.system.colorScheme == nil, "System delegates appearance to macOS")
        let untouched = Data("existing-workspace-data".utf8)
        defaults.set(untouched, forKey: "keep.timesheet.v1")
        defaults.set(untouched, forKey: "keep.tasks.v1")
        guard let artistURL = URL(string: "https://audius.co/softloops"),
              let playlistURL = URL(string: "https://audius.co/softloops/playlist/late-afternoon") else { throw CocoaError(.coderInvalidValue) }
        let artist = MusicChannel(resourceID: "artist1", name: "Soft loops", kind: .artist, url: artistURL)
        let playlist = MusicChannel(resourceID: "list1", name: "Late afternoon", kind: .playlist, url: playlistURL)
        preferences.appearance = .dark
        preferences.wallpaperSource = .audius
        preferences.wallpaperOrder = .shuffle
        preferences.rotationSeconds = 300
        preferences.automaticallyRotate = false
        preferences.loopWallpapers = false
        preferences.glassStyle = .liquid
        preferences.glassiness = 0.8
        preferences.saveChannel(artist); preferences.saveChannel(playlist); preferences.saveChannel(artist)
        expect(preferences.snapshot.channels.count == 2, "Saving a duplicate updates metadata rather than duplicating channels")
        preferences.selectChannel(playlist)
        let reopened = AppPreferences(persistence: persistence)
        expect(reopened.snapshot == preferences.snapshot && reopened.selectedChannel == playlist, "Reload appearance, material, artwork, rotation, and selected playlist")
        expect(defaults.data(forKey: "keep.timesheet.v1") == untouched && defaults.data(forKey: "keep.tasks.v1") == untouched, "Settings never overwrite timer or task archives")
        preferences.removeChannel(artist)
        expect(preferences.selectedChannel == playlist && preferences.snapshot.channels == [playlist], "Removing another saved channel preserves selection")
        preferences.removeChannel(playlist)
        expect(preferences.selectedChannel == nil && preferences.snapshot.channels.isEmpty, "Removing selected channel restores all-lofi source")
        preferences.glassiness = 10
        expect(preferences.glassiness == 1, "Clamp glassiness upper bound")
        preferences.glassiness = -1
        expect(preferences.glassiness == 0, "Clamp glassiness lower bound")
        preferences.glassiness = .nan
        expect(preferences.glassiness == 0.45, "Reject nonfinite glassiness")
        preferences.rotationSeconds = -1
        expect(preferences.rotationSeconds == 300, "Reject invalid rotation interval")
        let invalid = MusicChannel(resourceID: "../bad", name: "Bad", kind: .artist, url: artist.url)
        preferences.saveChannel(invalid)
        expect(preferences.snapshot.channels.isEmpty, "Reject channel path injection before persistence")
        preferences.selectChannel(artist)
        expect(preferences.selectedChannel == nil, "Selection must reference a saved channel")

        defaults.set(Data("broken".utf8), forKey: persistence.key)
        let blocked = AppPreferences(persistence: persistence)
        blocked.appearance = .system; blocked.saveChannel(artist); blocked.clearFolder()
        expect(!blocked.canEdit && blocked.persistenceError != nil, "Invalid archive protects saved preferences and blocks changes")
        expect(defaults.data(forKey: persistence.key) == Data("broken".utf8), "Blocked edits never overwrite invalid saved data")
        try persistence.save(SettingsArchive())
        blocked.retryPersistence()
        expect(blocked.canEdit && blocked.persistenceError == nil, "Retry recovers after archive is repaired")
        var corrupt = SettingsArchive(); corrupt.glassiness = 2
        defaults.set(try JSONEncoder().encode(corrupt), forKey: persistence.key)
        do { _ = try persistence.load(); expect(false, "Reject invalid numeric preferences") }
        catch { expect(true, "Reject invalid numeric preferences on reload") }
        corrupt = SettingsArchive(); corrupt.channels = [artist, artist]
        defaults.set(try JSONEncoder().encode(corrupt), forKey: persistence.key)
        do { _ = try persistence.load(); expect(false, "Reject duplicate channel identities") }
        catch { expect(true, "Reject duplicate channel identities on reload") }
        try persistence.save(SettingsArchive())

        var cycle = WallpaperCycle()
        cycle.reset(count: 3, shuffled: false)
        expect(cycle.current == 0, "Sequential cycle starts at first image")
        expect(cycle.advance(loop: false, shuffled: false) == 1 && cycle.advance(loop: false, shuffled: false) == 2, "Sequential rotation visits images in order")
        expect(cycle.advance(loop: false, shuffled: false) == nil && cycle.current == 2, "No-loop rotation stops on final image")
        expect(cycle.advance(loop: true, shuffled: false) == 0, "Loop wraps sequential rotation")
        cycle.reset(count: 0, shuffled: true)
        expect(cycle.current == nil && cycle.advance(loop: true, shuffled: true) == nil, "Empty wallpaper folder cannot rotate")
        cycle.reset(count: 1, shuffled: true)
        expect(cycle.advance(loop: true, shuffled: true) == 0 && cycle.advance(loop: false, shuffled: true) == nil, "Single-image cycles obey looping")
        for _ in 0..<15 {
            cycle.reset(count: 8, shuffled: true)
            var seen = Set<Int>()
            if let index = cycle.current { seen.insert(index) }
            for _ in 1..<8 { if let index = cycle.advance(loop: false, shuffled: true) { seen.insert(index) } }
            expect(seen.count == 8, "Shuffle has no duplicates within a cycle")
            let last = cycle.current
            expect(cycle.advance(loop: true, shuffled: true) != last, "New shuffled cycle avoids an immediate repeated image")
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keep-wallpapers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("one.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.copyItem(at: folder.appendingPathComponent("one.png"), to: folder.appendingPathComponent("two.png"))
        try FileManager.default.copyItem(at: folder.appendingPathComponent("one.png"), to: folder.appendingPathComponent(".hidden.png"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("escape.png"), withDestinationURL: folder.appendingPathComponent("one.png"))
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("note.txt"))
        let folderPreferences = AppPreferences(persistence: persistence)
        let library = WallpaperLibrary()
        library.chooseFolder(folder, preferences: folderPreferences)
        await settle(library)
        expect(folderPreferences.snapshot.folderBookmark != nil && folderPreferences.wallpaperSource == .folder, "Folder choice saves a security-scoped bookmark and selects folder source")
        expect(library.count == 2 && library.image != nil && library.error == nil, "Read real image thumbnails; ignore hidden files, symlinks, and nonimages")
        let restored = AppPreferences(persistence: persistence), restoredLibrary = WallpaperLibrary()
        restoredLibrary.configure(restored.snapshot.wallpaperConfiguration, preferences: restored)
        await settle(restoredLibrary)
        expect(restoredLibrary.count == 2 && restoredLibrary.image != nil, "Resolve saved bookmark and reload folder images")
        restoredLibrary.next()
        await settle(restoredLibrary)
        expect(restoredLibrary.image != nil && restoredLibrary.error == nil, "Manual wallpaper navigation remains available")
        restored.wallpaperSource = .cozy
        restoredLibrary.configure(restored.snapshot.wallpaperConfiguration, preferences: restored)
        expect(restoredLibrary.image == nil && !restoredLibrary.isLoading, "Changing wallpaper source clears folder presentation")
        restored.clearFolder()
        expect(restored.snapshot.folderBookmark == nil && restored.snapshot.folderName == nil, "Removing folder discards its bookmark")
        library.shutdown(); restoredLibrary.shutdown()
        try FileManager.default.removeItem(at: folder)
        let missingLibrary = WallpaperLibrary()
        missingLibrary.configure(folderPreferences.snapshot.wallpaperConfiguration, preferences: folderPreferences)
        await settle(missingLibrary)
        expect(missingLibrary.image == nil && missingLibrary.error != nil && !missingLibrary.isLoading, "Missing folder has actionable error and cozy fallback")
        missingLibrary.shutdown()
        let processSuite = "keep.preferences.process.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: processSuite) }
        for mode in ["write", "read"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [mode, processSuite]
            try process.run(); process.waitUntilExit()
            expect(process.terminationStatus == 0, "Preferences survive \(mode) subprocess")
        }
        print("Passed \(checks) preferences and wallpaper checks")
    }

    @MainActor static func settle(_ library: WallpaperLibrary) async {
        for _ in 0..<200 {
            if !library.isLoading { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
