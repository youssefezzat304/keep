import AppKit
import SwiftUI

/// Exercises the actual SwiftUI-generated menu in an isolated app with silent audio.
@main struct MusicShortcutChecks: App {
    @State private var preferences: AppPreferences
    @State private var player: MusicPlayerModel

    init() {
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _player = State(initialValue: MusicPlayerModel(catalog: AudiusClient(), playback: SilentPlayback(), preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            Text("Isolated shortcut checks")
                .frame(width: 400, height: 200)
                .task { await checkMenu() }
        }
        .commands { MusicCommands(player: player, preferences: preferences) }
    }

    private func checkMenu() async {
        do {
            try await Task.sleep(for: .milliseconds(400))
            guard let menu = NSApp.mainMenu, let window = NSApp.windows.first(where: { $0.isVisible }) else {
                preconditionFailure("Missing native menu/window")
            }
            let items = allItems(menu)
            let minimize = items.first { $0.title == "Minimize" }
            precondition(minimize != nil && minimize?.keyEquivalent.isEmpty == true, "Minimize remains available without Command-M")
            precondition(items.contains { $0.title == "Zoom" }, "Zoom remains available")
            let mute = items.filter { $0.keyEquivalent == "m" && $0.keyEquivalentModifierMask == .command }
            precondition(mute.count == 1 && mute.first?.title == "Mute / Unmute Music", "Command-M has exactly one menu owner")

            player.volume = 0.37
            let editor = NSTextField(string: "Keep this task draft")
            editor.frame = NSRect(x: 20, y: 20, width: 250, height: 24)
            window.contentView?.addSubview(editor)
            window.makeKey()
            precondition(window.makeFirstResponder(editor), "Focus the task-like field")
            let wallpapers = WallpaperShortcutView()
            wallpapers.enabled = true
            var moves: [Int] = []
            wallpapers.onMove = { moves.append($0) }
            window.contentView?.addSubview(wallpapers)
            guard let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{f703}",
                charactersIgnoringModifiers: "\u{f703}", isARepeat: false, keyCode: 124) else {
                preconditionFailure("Cannot create wallpaper event")
            }
            NSApp.sendEvent(right)
            precondition(moves == [1] && editor.stringValue == "Keep this task draft", "Native wallpaper routing works while editing without changing the draft")
            wallpapers.detach()
            guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "m",
                charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46) else {
                preconditionFailure("Cannot create Command-M event")
            }
            precondition(menu.performKeyEquivalent(with: key) && player.volume == 0, "Command-M mutes through the native menu while editing")
            precondition(!window.isMiniaturized && editor.stringValue == "Keep this task draft", "Mute preserves the window and draft")
            try await Task.sleep(for: .milliseconds(100))
            NSApp.mainMenu?.items.first(where: { $0.title == "Music" })?.submenu?.update()
            precondition(NSApp.mainMenu.map(allItems)?.contains { $0.title == "Mute / Unmute Music" } == true, "Menu keeps the toggle discoverable in both states")
            precondition(menu.performKeyEquivalent(with: key) && player.volume == 0.37, "Command-M restores the previous volume")
            precondition(!window.isMiniaturized, "Unmute does not minimize")
            await player.shutdown()?.value
            print("Passed 10 native shortcut checks")
            NSApp.terminate(nil)
        } catch {
            preconditionFailure("Shortcut checks failed: \(error)")
        }
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
    }
}

private final class SilentPlayback: MusicPlayback {
    var volume: Float = 0.5
    func load(_ url: URL, autoplay: Bool, onEvent: @escaping @MainActor (MusicPlaybackEvent) -> Void) {}
    func play() {}
    func pause() {}
    func stop() {}
}
