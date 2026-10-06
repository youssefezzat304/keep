import SwiftUI

struct ZenSavedMusicPicker: View {
    let player: MusicPlayerModel
    let preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your saved listens").font(.system(size: 20, design: .serif))
            if preferences.snapshot.channels.isEmpty {
                Text("Save an artist or playlist with the heart, or add an Audius link in Settings.")
                    .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                KeepScrollView {
                    VStack(spacing: 6) {
                        ForEach(preferences.snapshot.channels) { channel in
                            Button { play(channel) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: channel.symbol).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(channel.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(channel.subtitle).font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: player.selectedChannel?.id == channel.id ? "checkmark" : "play.fill")
                                        .font(.system(size: 11))
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(ZenSavedMusicRowStyle()).disabled(!preferences.canEdit)
                            .help(channel.name)
                            .accessibilityLabel("Play saved \(channel.subtitle.lowercased()): \(channel.name)")
                            .accessibilityAddTraits(player.selectedChannel?.id == channel.id ? .isSelected : [])
                        }
                    }
                }
                .frame(height: min(CGFloat(preferences.snapshot.channels.count) * 59, 270))
                .accessibilityLabel("Saved Audius artists and playlists")
            }
        }
        .padding(16).frame(width: 320, alignment: .leading)
        .foregroundStyle(KeepTheme.ink)
    }

    private func play(_ channel: MusicChannel) {
        guard preferences.canEdit else { return }
        player.selectProvider(.audius)
        preferences.selectChannel(channel)
        if player.selectedChannel?.id != channel.id { player.selectChannel(channel, autoplay: true) }
        else if case .failed = player.state { player.retry() }
        else if !player.wantsPlayback { player.togglePlayback() }
    }
}

private struct ZenSavedMusicRowStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(KeepTheme.mutedWarm.opacity(hovered || configuration.isPressed ? 0.65 : 0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8)).onHover { hovered = $0 }
    }
}
