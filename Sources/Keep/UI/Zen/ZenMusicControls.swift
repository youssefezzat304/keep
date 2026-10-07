import SwiftUI

struct ZenMusicControls: View {
    @Bindable var player: MusicPlayerModel
    let preferences: AppPreferences
    let wallpapers: WallpaperLibrary
    @State private var showsLibrary = false
    @State private var showsSavedChannels = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.musicLibraryViewport) private var artworkSize

    private var favoriteTarget: MusicChannel? { player.selectedChannel ?? player.track?.artistChannel }
    private var isFavorite: Bool { favoriteTarget.map { target in preferences.snapshot.channels.contains { $0.id == target.id } } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsSavedChannels, player.provider == .audius {
                ZenSavedMusicPicker(player: player, preferences: preferences)
                    .modifier(MusicGlassPanel(preferences: preferences, wallpapers: wallpapers,
                                              artworkSize: artworkSize, artworkCoordinateSpace: "zenArtwork"))
                    .padding(.bottom, 9)
                    .transition(.opacity)
            }
            HStack(spacing: 3) {
                control(player.wantsPlayback ? "pause.fill" : "play.fill", label: player.wantsPlayback ? "Pause music" : "Play music") { player.togglePlayback() }
                control("backward.end.fill", label: "Previous track", disabled: !player.canSkip) { player.previous() }
                control("forward.end.fill", label: "Next track", disabled: !player.canSkip) { player.next() }
                control(player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", label: player.volume == 0 ? "Unmute music" : "Mute music", disabled: !preferences.canEdit) { player.toggleMute() }
                Slider(value: $player.volume, in: 0...1)
                    .focusedValue(\.wallpaperArrowKeysReserved, true)
                    .frame(width: 92).tint(.white).environment(\.colorScheme, .dark)
                    .disabled(!preferences.canEdit).accessibilityLabel("Music volume")
                    .accessibilityValue("\(Int(player.volume * 100)) percent")
                if player.provider == .appleMusic {
                    control("music.note.list", label: "Browse Music library") { showsLibrary = true }
                } else {
                    control(isFavorite ? "heart.fill" : "heart", label: isFavorite ? "Unsave current artist or playlist" : "Save current artist or playlist", disabled: favoriteTarget == nil || !preferences.canEdit) {
                        guard let target = favoriteTarget else { return }
                        if isFavorite { preferences.removeChannel(target) }
                        else { preferences.saveChannel(target) }
                    }
                    .accessibilityValue(favoriteTarget.map { "\($0.name), \(isFavorite ? "saved" : "not saved")" } ?? "Play music to discover an artist")
                    control("list.bullet", label: "Saved artists and playlists") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsSavedChannels.toggle() }
                    }
                        .accessibilityValue(showsSavedChannels ? "Expanded" : "Collapsed")
                }
            }
            HStack(spacing: 6) {
                if player.state == .loading {
                    ProgressView().controlSize(.mini).colorScheme(.dark).accessibilityLabel("Loading music")
                }
                if player.provider == .audius, let url = player.track?.permalink ?? player.selectedChannel?.url {
                    Link(destination: url) { trackCaption }.buttonStyle(.plain)
                } else {
                    trackCaption
                }
            }
            .padding(.leading, 8)
            if case .failed(let failure) = player.state {
                HStack(alignment: .top, spacing: 8) {
                    Text(failure.message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { player.retry() }.buttonStyle(ZenControlStyle())
                }
                .padding(.leading, 8)
            }
        }
        .foregroundStyle(.white).shadow(color: .black.opacity(0.65), radius: 3, y: 1)
        .sheet(isPresented: $showsLibrary) {
            AppleMusicLibraryView(player: player, preferences: preferences, wallpapers: wallpapers)
        }
        .onChange(of: player.provider) { _, provider in
            if provider != .audius { showsSavedChannels = false }
            if provider != .appleMusic { showsLibrary = false }
        }
    }

    private var trackCaption: some View {
        Text(player.track.map { "\($0.title) · \($0.artist)" } ?? player.provider.title)
            .font(.system(size: 12, design: .monospaced)).lineLimit(1)
            .help(player.track?.title ?? player.provider.title)
    }

    private func control(_ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }
            .buttonStyle(ZenControlStyle()).disabled(disabled).accessibilityLabel(label).help(label)
    }
}
