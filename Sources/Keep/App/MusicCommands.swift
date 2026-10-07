import AppKit
import SwiftUI

/// Native menu shortcuts use the same app-owned player as every workspace window.
struct MusicCommands: Commands {
    let player: MusicPlayerModel
    let preferences: AppPreferences

    var body: some Commands {
        CommandMenu("Music") {
            MusicMuteButton(player: player, preferences: preferences)
        }
        // Command-M belongs to mute in Keep. Retain the native window actions
        // without advertising a second, conflicting Command-M equivalent.
        CommandGroup(replacing: .windowSize) {
            Button("Minimize") {
                NSApp.sendAction(#selector(NSWindow.performMiniaturize(_:)), to: nil, from: nil)
            }
            Button("Zoom") {
                NSApp.sendAction(#selector(NSWindow.performZoom(_:)), to: nil, from: nil)
            }
        }
    }
}

/// Keep preference observation in a View for the native command’s enabled state.
private struct MusicMuteButton: View {
    let player: MusicPlayerModel
    let preferences: AppPreferences

    var body: some View {
        Button("Mute / Unmute Music") { player.toggleMute() }
            .keyboardShortcut("m", modifiers: .command)
            .disabled(!preferences.canEdit)
    }
}
