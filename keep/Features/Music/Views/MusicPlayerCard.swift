import SwiftUI

struct MusicPlayerCard: View {
    @Bindable var player: MusicPlayerModel
    var preferences = AppPreferences()
    var wallpapers = WallpaperLibrary()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                MusicArtworkView(preferences: preferences, wallpapers: wallpapers)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("THE LISTENING CORNER", systemImage: "waveform")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(KeepTheme.paper.opacity(0.95), in: Capsule())
                        Spacer(minLength: 4)
                        if preferences.wallpaperSource == .folder {
                            musicControl("photo.badge.arrow.down", label: "Next wallpaper", disabled: !wallpapers.canAdvance) { wallpapers.next() }
                                .background(KeepTheme.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
                        }
                        channelMenu
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(player.track?.title ?? "Slow afternoons")
                                    .font(.system(size: 23, design: .serif))
                                    .lineLimit(1)
                                    .help(player.track?.title ?? "Slow afternoons")
                                Text(player.track?.artist ?? "Lofi for a little focus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(KeepTheme.secondaryInk)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if let url = player.track?.permalink ?? URL(string: "https://audius.co") {
                                Link("Audius ↗", destination: url)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(KeepTheme.accentStrong)
                                    .help("Open on Audius")
                            }
                        }
                        status
                        HStack(spacing: 8) {
                            musicControl("backward.end.fill", label: "Previous track", disabled: !player.canSkip) { player.previous() }
                            Button { player.togglePlayback() } label: {
                                Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(KeepTheme.paper)
                                    .frame(width: 42, height: 42)
                                    .background(KeepTheme.ink, in: Circle())
                            }
                            .buttonStyle(MusicControlStyle())
                            .accessibilityLabel(player.wantsPlayback ? "Pause music" : "Play music")
                            .help(player.wantsPlayback ? "Pause music" : "Play music")
                            musicControl("forward.end.fill", label: "Next track", disabled: !player.canSkip) { player.next() }
                            Spacer(minLength: 4)
                            musicControl(player.volume == 0 ? "speaker.slash" : "speaker.wave.2", label: player.volume == 0 ? "Unmute music" : "Mute music") {
                                player.toggleMute()
                            }
                            Slider(value: $player.volume, in: 0...1)
                                .frame(minWidth: 55, idealWidth: 80, maxWidth: 100)
                                .tint(KeepTheme.accentStrong)
                                .accessibilityLabel("Music volume")
                                .accessibilityValue("\(Int(player.volume * 100)) percent")
                        }
                    }
                    .padding(16)
                    .modifier(MusicGlassPanel(preferences: preferences))
                }
                .padding(16)
            }
            .foregroundStyle(KeepTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 288, maxHeight: .infinity)
    }

    private var channelMenu: some View {
        Menu {
            Button {
                guard player.selectedChannel != nil else { return }
                preferences.selectChannel(nil)
                player.selectChannel(nil)
            } label: {
                Label("All lofi", systemImage: player.selectedChannel == nil ? "checkmark" : "waveform")
            }
            if !preferences.snapshot.channels.isEmpty { Divider() }
            ForEach(preferences.snapshot.channels) { channel in
                Button {
                    guard player.selectedChannel?.id != channel.id else { return }
                    preferences.selectChannel(channel)
                    player.selectChannel(channel)
                } label: {
                    Label(channel.name, systemImage: player.selectedChannel?.id == channel.id ? "checkmark" : channel.symbol)
                }
            }
            if let artist = player.track?.artistChannel {
                Divider()
                Button {
                    preferences.saveChannel(artist)
                } label: {
                    Label(preferences.snapshot.channels.contains(where: { $0.id == artist.id }) ? "Artist saved" : "Save this artist", systemImage: "bookmark")
                }
                .disabled(!preferences.canEdit || preferences.snapshot.channels.contains { $0.id == artist.id })
            }
            if preferences.snapshot.channels.isEmpty {
                Text("Save artists & playlists in Settings")
            }
        } label: {
            Label(player.selectedChannel?.name ?? "All lofi", systemImage: "bookmark")
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
                .frame(maxWidth: 130)
        }
        .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(KeepTheme.paper.opacity(0.95), in: Capsule())
        .disabled(!preferences.canEdit)
        .accessibilityLabel("Music channel: \(player.selectedChannel?.name ?? "All lofi")")
        .help("Choose a saved Audius artist or playlist")
    }

    @ViewBuilder private var status: some View {
        switch player.state {
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 5) {
                Label(failure.message, systemImage: failure == .connection ? "wifi.exclamationmark" : "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(KeepTheme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { player.retry() }
                    .font(.system(size: 12, weight: .medium))
                    .tint(KeepTheme.accentStrong)
                    .help("Retry loading music")
            }
        case .loading:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(player.track == nil ? "Finding your next listen…" : "Connecting to the stream…")
            }
            .font(.system(size: 12))
            .foregroundStyle(KeepTheme.secondaryInk)
            .accessibilityElement(children: .combine)
        case .idle, .paused, .playing:
            Text(player.state == .playing ? "Playing · Audius" : player.state == .paused ? "Paused · Take your time" : "Press play to settle in")
                .font(.system(size: 12))
                .foregroundStyle(KeepTheme.secondaryInk)
        }
    }

    private func musicControl(_ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 30, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(MusicControlStyle())
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct MusicControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .background(KeepTheme.mutedWarm.opacity(configuration.isPressed ? 0.5 : hovered ? 0.3 : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(isFocused ? KeepTheme.focusRing : .clear, lineWidth: 2) }
            .onHover { hovered = $0 }
    }
}

#Preview {
    MusicPlayerCard(player: MusicPlayerModel()).padding().frame(width: 450, height: 330)
}
