import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: AppPreferences
    @Bindable var player: MusicPlayerModel
    var wallpapers: WallpaperLibrary
    var loginItem = LoginItemModel()
    var updater = AppUpdater()
    var isVisible = true
    @Environment(\.scenePhase) private var scenePhase
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
                    .font(KeepTheme.headingFont(size: 36))
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

            musicPermissions

            section("Startup", symbol: "power") {
                Toggle("Start on login", isOn: Binding(get: { loginItem.isEnabled }, set: { enabled in
                    Task { await loginItem.setEnabled(enabled) }
                }))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 13))
                .disabled(loginItem.isChanging)
                helper("Open Keep when you log in to your Mac.")
                if loginItem.status == .requiresApproval {
                    helper("Allow Keep in System Settings → General → Login Items to finish enabling this.")
                } else if loginItem.status == .notFound {
                    helper("Keep couldn’t be found. Move the app to Applications and try again.")
                }
                if let error = loginItem.errorMessage { helper(error) }
                if loginItem.status == .requiresApproval || loginItem.errorMessage != nil {
                    Button("Open Login Items…") { loginItem.openSettings() }
                }
            }

            updates

            VStack(alignment: .leading, spacing: 18) {
                section("Appearance", symbol: "circle.lefthalf.filled") {
                    settingRow("Dark mode", detail: "System follows your Mac’s appearance.") {
                        appearanceChoices
                    }
                    Divider().overlay(KeepTheme.border).allowsHitTesting(false)
                    Label("A little glass", systemImage: "rectangle.on.rectangle")
                        .font(KeepTheme.headingFont(size: 18))
                    glassSettings
                }

                section("Menu bar", symbol: "menubar.rectangle") {
                    Toggle("Show Keep in the menu bar", isOn: $preferences.menuBarEnabled)
                        .toggleStyle(.switch).controlSize(.small)
                        .font(.system(size: 13))
                    settingRow("Timer beside the leaf", detail: "Control both timers, see today’s tasks, and control the selected music provider without opening the workspace.") {
                        KeepSelectionMenu(label: "Menu bar timer", selection: $preferences.menuBarTimer,
                                          options: MenuBarTimer.allCases, title: { $0.title })
                            .frame(width: 160)
                    }
                    .disabled(!preferences.menuBarEnabled)
                }

                section("Music player", symbol: "photo.on.rectangle") {
                    settingRow("Apple Music", detail: "Uses the account signed in to Music on this Mac. Search and play your library inside Keep. Choose Track artwork to use available cover art; your volume is saved for both providers.") {
                        Button("Open Music…") { player.openAppleMusic() }
                    }
                    Divider().overlay(KeepTheme.border).allowsHitTesting(false)
                    settingRow("Wallpaper", detail: "Your backdrop for a slower afternoon.") {
                        KeepSelectionMenu(label: "Wallpaper source", selection: $preferences.wallpaperSource,
                                          options: WallpaperSource.allCases, title: { $0.title }).frame(width: 190)
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
                            KeepSelectionMenu(label: "Wallpaper order", selection: $preferences.wallpaperOrder,
                                              options: WallpaperOrder.allCases, title: { $0.title }).frame(width: 160)
                        }
                        settingRow("Change every") {
                            KeepSelectionMenu(label: "Wallpaper rotation interval", selection: $preferences.rotationSeconds,
                                              options: SettingsArchive.rotationIntervals, title: { seconds in
                                seconds == 30 ? "30 seconds" : "\(seconds / 60) minute\(seconds == 60 ? "" : "s")"
                            }).frame(width: 160)
                        }.disabled(!preferences.automaticallyRotate)
                        Toggle("Loop after the last wallpaper", isOn: $preferences.loopWallpapers)
                            .disabled(!preferences.automaticallyRotate)
                    }
                    .font(.system(size: 13))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(preferences.wallpaperSource != .folder)

                    if preferences.wallpaperSource == .audius {
                        helper("Displays the current track’s artwork. It changes with each track; missing or unavailable artwork falls back to the cozy corner.")
                    } else if preferences.wallpaperSource == .folder {
                        helper("Shuffle visits each image once per cycle. Turn looping off to stop on the last image, or change images manually from the player.")
                    }
                }


                section("Saved Audius channels", symbol: "bookmark") {
                    helper("Save an artist profile or playlist link, then find it in the player’s channel menu. Audio starts only when you press Play.")
                    HStack(spacing: 10) {
                        TextField("Paste an Audius artist or playlist link…", text: $channelURL)
                            .modifier(KeepInputStyle())
                            .accessibilityLabel("Audius artist or playlist link")
                            .onSubmit { addChannel() }
                        if addingChannel { ProgressView().controlSize(.small).accessibilityLabel("Saving Audius channel") }
                        Button("Save channel") { addChannel() }
                            .buttonStyle(KeepButtonStyle(emphasis: .primary))
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
        }
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .buttonStyle(KeepButtonStyle())
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
        .task(id: isVisible) {
            if isVisible { loginItem.refresh(); await player.checkAppleMusicAccess() }
        }
        .onChange(of: scenePhase) { _, phase in
            if isVisible, phase == .active { loginItem.refresh(); Task { await player.checkAppleMusicAccess() } }
        }
    }

    private var updates: some View {
        section("Updates", symbol: "arrow.triangle.2.circlepath") {
            settingRow("Keep \(updater.configuration.version) (\(updater.configuration.build))") {
                if updater.restartGate.isPending {
                    Button("Restart to update…") { updater.requestRestart() }
                        .buttonStyle(KeepButtonStyle(emphasis: .primary))
                } else if !updater.isStarted, updater.status == .failed {
                    Button("Retry") { updater.start() }
                } else {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.isStarted || !updater.canCheckForUpdates)
                }
            }
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.setAutomaticallyChecksForUpdates($0) }
            ))
            .toggleStyle(.switch).controlSize(.small).font(.system(size: 13))
            .disabled(!updater.isStarted)
            helper(updater.statusText)
            if let date = updater.lastChecked {
                helper("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

    private var musicPermissions: some View {
        section("Permissions", symbol: "lock.shield") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Music").font(.system(size: 14, weight: .medium))
                    helper("Allow Keep to read your Music library and control playback. Requesting access won’t start a song.")
                }
                Spacer(minLength: 0)
                Text(player.appleMusicAccess.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(player.appleMusicAccess == .allowed ? KeepTheme.ink : KeepTheme.secondaryInk)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(KeepTheme.mutedWarm, in: Capsule())
                    .accessibilityLabel("Music permission: \(player.appleMusicAccess.title)")
            }
            HStack(spacing: 10) {
                Button(player.appleMusicAccess == .denied ? "Open System Settings…" : player.appleMusicAccess == .allowed ? "Check access" : "Allow Music access…") {
                    if player.appleMusicAccess == .denied { player.openMusicAutomationSettings() }
                    else { Task { await player.checkAppleMusicAccess(requestPermission: player.appleMusicAccess != .allowed) } }
                }
                .buttonStyle(KeepButtonStyle(emphasis: player.appleMusicAccess == .allowed ? .quiet : .primary))
                .disabled(player.appleMusicAccess == .checking)
                Button(player.appleMusicAccess == .denied ? "Check access" : "System Settings…") {
                    if player.appleMusicAccess == .denied { Task { await player.checkAppleMusicAccess() } }
                    else { player.openMusicAutomationSettings() }
                }
                .help(player.appleMusicAccess == .denied ? "Check Music access again" : "Open Privacy & Security → Automation")
            }
            if player.appleMusicAccess == .denied {
                helper("Enable Music under Keep in System Settings → Privacy & Security → Automation, then return here.")
            } else if player.appleMusicAccess == .failed {
                helper("Open Music and try again. You can also check access in System Settings → Privacy & Security → Automation.")
            }
        }
    }

    private var glassSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            MusicPlayerCard(player: player, preferences: preferences, wallpapers: wallpapers)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Music card preview")
            settingRow("Card material") {
                KeepSelectionMenu(label: "Music card material", selection: $preferences.glassStyle,
                                  options: MusicGlassStyle.allCases, title: { $0.title }).frame(width: 190)
            }
            HStack {
                Text("Glassiness").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int((preferences.glassiness * 100).rounded()))%")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(KeepTheme.mutedInk)
            }
            Slider(value: $preferences.glassiness, in: 0...1)
                .tint(KeepTheme.accentStrong)
                .frame(height: 44)
                .accessibilityLabel("Glassiness")
                .accessibilityValue("\(Int((preferences.glassiness * 100).rounded())) percent")
            HStack {
                Text("Solid paper")
                Spacer()
                Text("Clear glass")
            }.font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
        }
    }

    private var appearanceChoices: some View {
        HStack(spacing: 4) {
            ForEach(AppAppearance.allCases) { appearance in
                Button { preferences.appearance = appearance } label: {
                    HStack(spacing: 5) {
                        if preferences.appearance == appearance {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        }
                        Text(appearance.title)
                    }
                }
                .buttonStyle(KeepButtonStyle(emphasis: preferences.appearance == appearance ? .primary : .quiet))
                .accessibilityLabel("\(appearance.title) appearance")
                .accessibilityAddTraits(preferences.appearance == appearance ? .isSelected : [])
            }
        }
        .padding(4)
        .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 14))
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol).font(KeepTheme.headingFont(size: 23))
            content()
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
    }
    private func settingRow<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                settingLabel(title, detail: detail)
                Spacer(minLength: 8)
                content().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 12) {
                settingLabel(title, detail: detail)
                content()
            }
        }
    }
    private func settingLabel(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium))
            if let detail { helper(detail) }
        }
    }
    private func helper(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
    }
    private func select(_ channel: MusicChannel, autoplay: Bool) {
        player.selectProvider(.audius)
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
