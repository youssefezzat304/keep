import SwiftUI

extension EnvironmentValues {
    @Entry var musicLibraryViewport = CGSize(width: 1000, height: 900)
}

struct AppleMusicLibraryView: View {
    @Bindable var player: MusicPlayerModel
    let preferences: AppPreferences
    let wallpapers: WallpaperLibrary
    @State private var library: AppleMusicLibraryModel
    @Environment(\.musicLibraryViewport) private var viewport
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AppleMusicItem.Kind = .songs
    @State private var query = ""
    @State private var playlist: AppleMusicItem?
    @State private var offset = 0
    @State private var revision = 0
    @State private var seekDraft: Double?
    private struct LoadKey: Equatable { let request: AppleMusicLibraryRequest; let revision: Int }
    private var loadKey: LoadKey {
        LoadKey(request: AppleMusicLibraryRequest(kind: kind, query: query, playlist: playlist, offset: offset), revision: revision)
    }

    init(player: MusicPlayerModel, preferences: AppPreferences, wallpapers: WallpaperLibrary) {
        self.player = player
        self.preferences = preferences
        self.wallpapers = wallpapers
        _library = State(initialValue: player.makeAppleLibrary())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Apple Music").font(.system(size: 28, design: .serif))
                    Text("Songs and playlists in your Music library").font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if player.track != nil { nowPlaying }
            else if player.state == .loading {
                ProgressView("Connecting to Music…").controlSize(.small)
            }
            if case .failed(let failure) = player.state {
                HStack(alignment: .top) {
                    Text(failure.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Retry playback") { player.retry() }
                }.foregroundStyle(KeepTheme.accentStrong)
            }
            HStack {
                if let playlist {
                    Button { self.playlist = nil; query = ""; offset = 0 } label: {
                        Label("Playlists", systemImage: "chevron.left")
                    }
                    Text(playlist.title).font(.system(size: 14, weight: .medium)).lineLimit(1).help(playlist.title)
                    Spacer()
                    Button("Play playlist") { player.playAppleItem(playlist) }.disabled(!preferences.canEdit)
                } else {
                    Picker("Browse library", selection: $kind) {
                        Text("Songs").tag(AppleMusicItem.Kind.songs)
                        Text("Playlists").tag(AppleMusicItem.Kind.playlists)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                    Spacer()
                    Button { offset = 0; revision += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh Music library").help("Refresh Music library")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(KeepTheme.secondaryInk)
                TextField(playlist == nil ? "Search your library" : "Search this playlist", text: $query)
                    .textFieldStyle(.plain).accessibilityLabel("Search Music library")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(12).background(KeepTheme.mutedWarm, in: RoundedRectangle(cornerRadius: 10))
            libraryContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        }
        .padding(24).frame(width: min(620, viewport.width - 48), height: min(720, viewport.height - 64))
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
        .buttonStyle(KeepButtonStyle())
        .preferredColorScheme(preferences.appearance.colorScheme)
        .task { await player.observeAppleMusic() }
        .task(id: loadKey) {
            do {
                if !query.isEmpty { try await Task.sleep(for: .milliseconds(350)) }
                try Task.checkCancellation()
                await library.load(loadKey.request, append: offset > 0)
            } catch is CancellationError { /* A newer search owns the results. */ }
            catch { assertionFailure("Unexpected search delay failure") }
        }
        .onChange(of: query) { _, _ in offset = 0 }
        .onChange(of: kind) { _, _ in query = ""; offset = 0 }
        .onDisappear { library.cancel() }
    }

    @ViewBuilder private var libraryContent: some View {
        switch library.state {
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 12) {
                Text(failure.message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Button("Retry") { offset = 0; revision += 1 }
            }
        case .idle, .loading, .ready:
            if library.items.isEmpty {
                if library.state == .ready {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(query.isEmpty ? "Nothing here yet" : "No matches in your library").font(.system(size: 22, design: .serif))
                        Text(query.isEmpty ? "Add songs or playlists in Music, then refresh your library here." : "Try another title, artist, or album.")
                            .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                    }.padding(.vertical, 24)
                } else { ProgressView("Reading your Music library…").padding(.vertical, 24) }
            } else {
                KeepScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(library.items) { item in
                            libraryRow(item)
                        }
                        if library.state == .loading { ProgressView().padding(10) }
                        else if library.hasMore {
                            Button("Load more") { offset += AppleMusicLibraryRequest.pageSize }.padding(10)
                        }
                    }
                }
                .accessibilityLabel(playlist?.title ?? (kind == .songs ? "Music library songs" : "Music library playlists"))
            }
        }
    }

    private func libraryRow(_ item: AppleMusicItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if item.kind == .playlists { playlist = item; query = ""; offset = 0 }
                else { player.playAppleItem(item) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.kind == .songs ? "music.note" : "music.note.list")
                        .foregroundStyle(KeepTheme.accentStrong).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(item.artist).font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: item.kind == .songs ? "play.fill" : "chevron.right").font(.system(size: 11))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(item.kind == .songs && !preferences.canEdit)
                .accessibilityLabel("\(item.kind == .songs ? "Play" : "Browse playlist") \(item.title), \(item.artist)")
                .help(item.title)
        }.padding(10).background(KeepTheme.mutedWarm.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let image = wallpapers.trackImage {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.track?.title ?? "").font(.system(size: 17, design: .serif)).lineLimit(1).help(player.track?.title ?? "")
                    Text(player.track?.artist ?? "").font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Previous track").disabled(!player.canSkip)
                Button { player.togglePlayback() } label: { Image(systemName: player.wantsPlayback ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(player.wantsPlayback ? "Pause music" : "Play music")
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next track").disabled(!player.canSkip)
                Button { player.toggleAppleShuffle() } label: { Image(systemName: "shuffle") }
                    .buttonStyle(KeepButtonStyle(emphasis: player.appleShuffled ? .primary : .quiet))
                    .accessibilityLabel("Shuffle").accessibilityValue(player.appleShuffled ? "On" : "Off")
                Button { player.cycleAppleRepeat() } label: { Image(systemName: player.appleRepeat == .one ? "repeat.1" : "repeat") }
                    .buttonStyle(KeepButtonStyle(emphasis: player.appleRepeat == .off ? .quiet : .primary))
                    .accessibilityLabel("Repeat").accessibilityValue(player.appleRepeat.rawValue)
            }
            .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            HStack {
                HStack(spacing: 7) {
                    if player.state == .loading { ProgressView().controlSize(.small) }
                    Text(player.state == .playing ? "Playing" : player.state == .loading ? "Connecting…" : "Paused")
                }.font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
                Spacer()
                Button { player.toggleMute() } label: { Image(systemName: player.volume == 0 ? "speaker.slash" : "speaker.wave.2") }
                    .accessibilityLabel(player.volume == 0 ? "Unmute music" : "Mute music").disabled(!preferences.canEdit)
                Slider(value: $player.volume, in: 0...1).frame(width: 95).tint(KeepTheme.accentStrong)
                    .accessibilityLabel("Music volume").disabled(!preferences.canEdit)
            }
            if player.appleDuration > 0 {
                HStack(spacing: 8) {
                    Text(time(seekDraft ?? player.applePosition)).monospacedDigit().frame(width: 38)
                    Slider(value: Binding(get: { seekDraft ?? min(player.appleDuration, player.applePosition) },
                        set: { value in
                            if seekDraft != nil { seekDraft = value }
                            else { player.seekApple(to: value) } // Keyboard/Accessibility changes commit directly.
                        }), in: 0...player.appleDuration) { editing in
                            if editing { seekDraft = player.applePosition }
                            else if let value = seekDraft { seekDraft = nil; player.seekApple(to: value) }
                        }.accessibilityLabel("Song position")
                        .accessibilityValue("\(time(seekDraft ?? player.applePosition)) of \(time(player.appleDuration))")
                        .tint(KeepTheme.accentStrong)
                    Text(time(player.appleDuration)).monospacedDigit().frame(width: 38)
                }.font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
            }
        }
        .padding(14).background(KeepTheme.mutedWarm.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: player.track?.id) { _, _ in seekDraft = nil }
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(min(86_400, max(0, seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
