import SwiftUI

struct MusicPlayerCard: View {
    @Bindable var player: MusicPlayerModel
    var preferences = AppPreferences()
    var wallpapers = WallpaperLibrary()
    @State private var showsSavedChannels = false
    @State private var channelMenuHovered = false
    @FocusState private var channelMenuFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var favoriteTarget: MusicChannel? { player.selectedChannel ?? player.track?.artistChannel }
    private var isFavorite: Bool { favoriteTarget.map { target in preferences.snapshot.channels.contains { $0.id == target.id } } ?? false }

    var body: some View {
        GeometryReader { geometry in
            // Reserve outer padding (32), the artwork header (46), and its gap (12).
            // The drawer only consumes the space already allocated to this card.
            let panelHeight = max(0, geometry.size.height - 90)
            ZStack(alignment: .bottom) {
                MusicArtworkView(preferences: preferences, wallpapers: wallpapers)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                VStack(alignment: .leading, spacing: 12) {
                    artworkHeader
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 10) {
                        if showsSavedChannels {
                            ViewThatFits(in: .vertical) {
                                VStack(alignment: .leading, spacing: 10) {
                                    savedHeading(showsActions: false)
                                    savedList(height: 160)
                                    Divider().overlay(KeepTheme.border).allowsHitTesting(false)
                                    playbackControls
                                }
                                .fixedSize(horizontal: false, vertical: true)

                                VStack(alignment: .leading, spacing: 10) {
                                    savedHeading(showsActions: true)
                                    // Reserve the heading (36), gap (10), and glass padding (32).
                                    savedList(height: max(1, panelHeight - 78))
                                }
                            }
                            .transition(.opacity)
                        } else {
                            playbackControls.transition(.opacity)
                        }
                    }
                    .padding(16)
                    .modifier(MusicGlassPanel(preferences: preferences, wallpapers: wallpapers, artworkSize: geometry.size))
                    .frame(maxHeight: panelHeight, alignment: .bottom)
                }
                .padding(16)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .foregroundStyle(KeepTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 288, maxHeight: .infinity)
    }

    private var artworkHeader: some View {
        HStack {
            if let url = player.track?.permalink ?? player.selectedChannel?.url ?? URL(string: "https://audius.co") {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Text("Audius")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KeepTheme.accentStrong)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(KeepTheme.paper.opacity(0.95), in: Capsule())
                }
                .buttonStyle(.plain).accessibilityLabel("Open on Audius").help("Open on Audius")
            }
            Spacer(minLength: 4)
            if preferences.wallpaperSource == .folder {
                musicControl("photo.badge.arrow.down", label: "Next wallpaper", disabled: !wallpapers.canAdvance) { wallpapers.next() }
                    .background(KeepTheme.paper.opacity(0.95), in: Circle())
            }
            channelMenu
        }
        .frame(height: 46)
    }

    private var playbackControls: some View {
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
                favoriteActions
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
                .buttonStyle(MusicControlStyle(isCircular: true))
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
    }

    private var favoriteActions: some View {
        HStack(spacing: 2) {
            musicControl(isFavorite ? "heart.fill" : "heart", label: isFavorite ? "Unsave current artist or playlist" : "Save current artist or playlist", disabled: favoriteTarget == nil || !preferences.canEdit) {
                guard let target = favoriteTarget else { return }
                if isFavorite { preferences.removeChannel(target) }
                else { preferences.saveChannel(target) }
            }
            .foregroundStyle(KeepTheme.accentStrong)
            .accessibilityValue(favoriteTarget.map { "\($0.name), \(isFavorite ? "saved" : "not saved")" } ?? "Play music to discover an artist")
            musicControl("list.bullet", label: "Saved music") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showsSavedChannels.toggle() }
            }
            .foregroundStyle(showsSavedChannels ? KeepTheme.accentStrong : KeepTheme.ink)
            .background(KeepTheme.mutedWarm.opacity(showsSavedChannels ? 0.5 : 0), in: Circle())
            .accessibilityValue(showsSavedChannels ? "Expanded" : "Collapsed")
        }
    }

    private func savedHeading(showsActions: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Your saved listens").font(.system(size: 21, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.75)
            Text("\(preferences.snapshot.channels.count)").font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
            Spacer(minLength: 4)
            if showsActions { favoriteActions }
        }
        .frame(height: 36)
    }

    private func savedList(height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if preferences.snapshot.channels.isEmpty {
                    Text("Keep a favorite close. Save an artist or playlist with the heart, or add an Audius link in Settings.")
                        .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                }
                ForEach(preferences.snapshot.channels) { channel in
                    Button { playSavedChannel(channel) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: channel.symbol).font(.system(size: 17)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(channel.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(channel.subtitle).font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: player.selectedChannel?.id == channel.id ? "checkmark" : "play.fill")
                                .font(.system(size: 11))
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(KeepTheme.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(MusicControlStyle()).disabled(!preferences.canEdit)
                    .accessibilityLabel("Play saved \(channel.subtitle.lowercased()): \(channel.name)")
                    .accessibilityAddTraits(player.selectedChannel?.id == channel.id ? .isSelected : [])
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Saved Audius artists and playlists")
    }

    private func playSavedChannel(_ channel: MusicChannel) {
        preferences.selectChannel(channel)
        if player.selectedChannel?.id != channel.id { player.selectChannel(channel, autoplay: true) }
        else if case .failed = player.state { player.retry() }
        else if !player.wantsPlayback { player.togglePlayback() }
        // Keep the drawer open through loading, playback, track changes, and pause.
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
            if preferences.snapshot.channels.isEmpty {
                Text("Save artists & playlists in Settings")
            }
        } label: {
            Label("Music source: \(player.selectedChannel?.name ?? "All lofi")", systemImage: "bookmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(KeepTheme.ink)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
        .frame(width: 46, height: 46)
        .background(KeepTheme.paper.opacity(channelMenuHovered ? 0.98 : 0.85), in: Circle())
        .contentShape(Circle())
        .onHover { channelMenuHovered = $0 }
        .focused($channelMenuFocused)
        .overlay { Circle().strokeBorder(channelMenuFocused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
        .disabled(!preferences.canEdit)
        .accessibilityLabel("Music channel: \(player.selectedChannel?.name ?? "All lofi")")
        .help("Music source: \(player.selectedChannel?.name ?? "All lofi")")
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
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(MusicControlStyle(isCircular: true))
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct MusicControlStyle: ButtonStyle {
    var isCircular = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .background {
                if isCircular { Circle().fill(KeepTheme.mutedWarm.opacity(configuration.isPressed ? 0.5 : hovered ? 0.3 : 0)) }
                else { RoundedRectangle(cornerRadius: 8).fill(KeepTheme.mutedWarm.opacity(configuration.isPressed ? 0.5 : hovered ? 0.3 : 0)) }
            }
            .overlay {
                if isCircular { Circle().strokeBorder(isFocused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
                else { RoundedRectangle(cornerRadius: 8).strokeBorder(isFocused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
            }
            .onHover { hovered = $0 }
    }
}

#Preview {
    MusicPlayerCard(player: MusicPlayerModel()).padding().frame(width: 450, height: 330)
}
