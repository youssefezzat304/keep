import SwiftUI

struct ZenSavedMusicPicker: View {
    let player: MusicPlayerModel
    let preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your listens").font(.system(size: 20, design: .serif))
            KeepScrollView {
                VStack(spacing: 6) {
                    sourceRow(nil)
                    ForEach(preferences.snapshot.channels) { channel in
                        sourceRow(channel)
                    }
                }
            }
            .frame(height: min(CGFloat(preferences.snapshot.channels.count + 1) * 59, 270))
            .accessibilityLabel("Audius listens")
        }
        .padding(16).frame(width: 320, alignment: .leading)
        .foregroundStyle(KeepTheme.ink)
    }

    private func sourceRow(_ channel: MusicChannel?) -> some View {
        let selected = player.provider == .audius && player.selectedChannel?.id == channel?.id
        return Button { player.playAudiusSource(channel) } label: {
            HStack(spacing: 10) {
                Image(systemName: channel?.symbol ?? "waveform").frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel?.name ?? "All Lofi").font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(channel?.subtitle ?? "Discover lofi music").font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark" : "play.fill").font(.system(size: 11))
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ZenSavedMusicRowStyle()).disabled(!preferences.canEdit)
        .help(channel?.name ?? "All Lofi")
        .accessibilityLabel(channel.map { "Play saved \($0.subtitle.lowercased()): \($0.name)" } ?? "Play All Lofi")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
