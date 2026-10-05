import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    @Bindable var player: MusicPlayerModel
    var wallpapers: WallpaperLibrary
    @State private var choosingFolder = false
    @State private var importError: String?
    @State private var channelURL = ""
    @State private var channelError: String?
    @State private var addingChannel = false
    @State private var channelRequest: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Make yourself at home.")
                    .font(.system(size: 36, design: .serif))
                Text("A few small touches for your focus space.")
                    .font(.system(size: 14)).foregroundStyle(KeepTheme.mutedInk)
            }
            if let error = preferences.persistenceError {
                HStack {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Retry") { preferences.retryPersistence() }
                }
                .font(.system(size: 13)).padding(14)
                .background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 18) {
                section("Appearance", symbol: "circle.lefthalf.filled") {
                    settingRow("Dark mode", detail: "System follows your Mac’s appearance.") {
                        Picker("Dark mode", selection: $preferences.appearance) {
                            ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                    }
                }

                section("Music player", symbol: "photo.on.rectangle") {
                    settingRow("Wallpaper", detail: "Your backdrop for a slower afternoon.") {
                        Picker("Wallpaper source", selection: $preferences.wallpaperSource) {
                            ForEach(WallpaperSource.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 190)
                    }

                    Divider().overlay(KeepTheme.border)
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(KeepTheme.accentStrong)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preferences.snapshot.folderName ?? "No wallpaper folder selected")
                                .font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text("Images directly inside the folder · read-only access")
                                .font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                        }
                        Spacer(minLength: 8)
                        Button(preferences.snapshot.folderBookmark == nil ? "Choose folder…" : "Change…") { choosingFolder = true }
                        if preferences.snapshot.folderBookmark != nil {
                            Button { preferences.clearFolder() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Remove wallpaper folder").help("Remove wallpaper folder")
                        }
                    }
                    if let error = importError ?? wallpapers.error {
                        HStack(alignment: .top) {
                            Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if preferences.wallpaperSource == .folder, preferences.snapshot.folderBookmark != nil {
                                Button("Retry") { importError = nil; wallpapers.retry(preferences: preferences) }
                            }
                        }
                    } else if preferences.wallpaperSource == .folder {
                        Text(wallpapers.isLoading ? "Opening your wallpapers…" : "\(wallpapers.count) images\(wallpapers.rotationFinished ? " · Rotation finished" : "")")
                            .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Rotate wallpapers automatically", isOn: $preferences.automaticallyRotate)
                        settingRow("Order") {
                            Picker("Wallpaper order", selection: $preferences.wallpaperOrder) {
                                ForEach(WallpaperOrder.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 160)
                        }
                        settingRow("Change every") {
                            Picker("Wallpaper rotation interval", selection: $preferences.rotationSeconds) {
                                ForEach(SettingsArchive.rotationIntervals, id: \.self) { seconds in
                                    Text(seconds == 30 ? "30 seconds" : "\(seconds / 60) minute\(seconds == 60 ? "" : "s")").tag(seconds)
                                }
                            }.labelsHidden().frame(width: 160)
                        }.disabled(!preferences.automaticallyRotate)
                        Toggle("Loop after the last wallpaper", isOn: $preferences.loopWallpapers)
                            .disabled(!preferences.automaticallyRotate)
                    }
                    .font(.system(size: 13))
                    .disabled(preferences.wallpaperSource != .folder)

                    if preferences.wallpaperSource == .audius {
                        helper("Displays the current track’s artwork. It changes with each track; missing or unavailable artwork falls back to the cozy corner.")
                    } else if preferences.wallpaperSource == .folder {
                        helper("Shuffle visits each image once per cycle. Turn looping off to stop on the last image, or change images manually from the player.")
                    }
                }

                section("A little glass", symbol: "rectangle.on.rectangle") {
                    settingRow("Card material") {
                        Picker("Music card material", selection: $preferences.glassStyle) {
                            ForEach(MusicGlassStyle.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 190)
                    }
                    HStack {
                        Text("Glassiness").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(preferences.glassiness * 100))%")
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(KeepTheme.mutedInk)
                    }
                    Slider(value: $preferences.glassiness, in: 0...1)
                        .accessibilityLabel("Music card glassiness")
                        .accessibilityValue("\(Int(preferences.glassiness * 100)) percent")
                    HStack {
                        Text("Solid paper")
                        Spacer()
                        Text("Clear glass")
                    }.font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                    helper("Adjusts material thickness and the warm tint over the image. Reduce Transparency on your Mac always uses solid paper.")
                }

                section("Saved Audius channels", symbol: "bookmark") {
                    helper("Save an artist profile or playlist link, then find it in the player’s channel menu. Audio starts only when you press Play.")
                    HStack(spacing: 10) {
                        TextField("Paste an Audius artist or playlist link…", text: $channelURL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Audius artist or playlist link")
                            .onSubmit { addChannel() }
                        if addingChannel { ProgressView().controlSize(.small).accessibilityLabel("Saving Audius channel") }
                        Button("Save channel") { addChannel() }
                            .disabled(addingChannel || channelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let channelError { Text(channelError).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong) }
                    if preferences.snapshot.channels.isEmpty {
                        Text("Your favorite listens will live here.")
                            .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).padding(.vertical, 4)
                    }
                    ForEach(preferences.snapshot.channels) { channel in
                        HStack(spacing: 12) {
                            Image(systemName: channel.symbol).font(.system(size: 19)).foregroundStyle(KeepTheme.accentStrong)
                            VStack(alignment: .leading, spacing: 3) {
                                Link(channel.name, destination: channel.url)
                                    .font(.system(size: 14, weight: .medium)).lineLimit(1).foregroundStyle(KeepTheme.ink)
                                Text(channel.subtitle).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                            }
                            Spacer(minLength: 8)
                            if player.selectedChannel?.id == channel.id {
                                Text("Selected").font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                            }
                            Button { select(channel, autoplay: true) } label: { Label("Play", systemImage: "play.fill") }
                                .accessibilityLabel("Play \(channel.name)")
                            Button {
                                if player.selectedChannel?.id == channel.id { player.selectChannel(nil) }
                                preferences.removeChannel(channel)
                            } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Remove saved channel \(channel.name)").help("Remove saved channel")
                        }.padding(.vertical, 6)
                    }
                }
            }
            .disabled(!preferences.canEdit)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): importError = nil; wallpapers.chooseFolder(url, preferences: preferences)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { importError = "The folder couldn’t be selected. Please try again." }
            }
        }
        .onDisappear { channelRequest?.cancel() }
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol).font(.system(size: 23, design: .serif))
            content()
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1) }
    }
    private func settingRow<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail { helper(detail) }
            }
            Spacer(minLength: 8)
            content()
        }
    }
    private func helper(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
    }
    private func select(_ channel: MusicChannel, autoplay: Bool) {
        preferences.selectChannel(channel)
        if player.selectedChannel?.id == channel.id {
            if autoplay && !player.wantsPlayback { player.togglePlayback() }
        } else { player.selectChannel(channel, autoplay: autoplay) }
    }
    private func addChannel() {
        guard preferences.canEdit, !addingChannel, !channelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = channelURL
        channelError = nil; addingChannel = true
        channelRequest?.cancel()
        channelRequest = Task {
            defer { addingChannel = false }
            do {
                let channel = try await AudiusClient().resolveChannel(text)
                try Task.checkCancellation()
                preferences.saveChannel(channel)
                if channelURL == text { channelURL = "" }
            } catch {
                guard !Task.isCancelled else { return }
                channelError = (error as? ChannelFailure)?.message ?? (error as? MusicFailure)?.message
                    ?? "The channel couldn’t be loaded. Check your connection and try again."
            }
        }
    }
}

#Preview("Settings") {
    SettingsView(preferences: AppPreferences(), player: MusicPlayerModel(), wallpapers: WallpaperLibrary())
        .padding(24).frame(width: 900).background(KeepTheme.paper)
}
