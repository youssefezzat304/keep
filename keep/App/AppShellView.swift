import SwiftUI

enum WorkspaceTab {
    case focus
    case dashboard
    case habits
    case stats
    case settings
}

struct AppShellView: View {
    @State private var workspace: WorkspaceModel
    @State private var music: MusicPlayerModel
    @State private var tasks: DailyTaskStore
    @State private var habits: HabitStore
    @State private var preferences: AppPreferences
    @State private var wallpapers: WallpaperLibrary
    @State private var selectedTab: WorkspaceTab
    @State private var loginItem: LoginItemModel
    @State private var zen: ZenModeModel
    @State private var updater: AppUpdater
    @Environment(\.self) private var environment

    init(initialTab: WorkspaceTab = .focus, workspace: WorkspaceModel = WorkspaceModel(), music: MusicPlayerModel = MusicPlayerModel(), tasks: DailyTaskStore? = nil, habits: HabitStore = HabitStore(), preferences: AppPreferences = AppPreferences(), wallpapers: WallpaperLibrary = WallpaperLibrary(), loginItem: LoginItemModel = LoginItemModel(), zen: ZenModeModel? = nil, updater: AppUpdater = AppUpdater()) {
        _workspace = State(initialValue: workspace)
        _music = State(initialValue: music)
        _tasks = State(initialValue: tasks ?? DailyTaskStore(habits: habits))
        _habits = State(initialValue: habits)
        _preferences = State(initialValue: preferences)
        _wallpapers = State(initialValue: wallpapers)
        _loginItem = State(initialValue: loginItem)
        _selectedTab = State(initialValue: initialTab)
        _updater = State(initialValue: updater)
        _zen = State(initialValue: zen ?? ZenModeModel())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 24) {
                    NavBar(
                        selection: selectedTab,
                        onSelectFocus: { selectedTab = .focus },
                        onSelectDashboard: { selectedTab = .dashboard },
                        onSelectHabits: { selectedTab = .habits },
                        onSelectStats: { selectedTab = .stats },
                        isCompact: geometry.size.width < 900,
                        onSelectSettings: { selectedTab = .settings }
                    )

                    if let message = workspace.persistenceError {
                        HStack {
                            Text(message).font(.system(size: 13))
                            Spacer()
                            Button("Retry") { workspace.retryPersistence() }
                        }
                        .padding(12)
                        .background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .contain)
                    }

                    // Each tab keeps its content and scroll position inside the same viewport.
                    ZStack(alignment: .top) {
                        GeometryReader { viewport in
                            KeepScrollView {
                                FocusSessionView(workspace: workspace, music: music, tasks: tasks, preferences: preferences, wallpapers: wallpapers, isCompact: geometry.size.width < 820, isActive: selectedTab == .focus && !zen.isPresented, minimumHeight: viewport.size.height, onEnterZen: { zen.enter() })
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .opacity(selectedTab == .focus ? 1 : 0)
                        .allowsHitTesting(selectedTab == .focus)
                        .accessibilityHidden(selectedTab != .focus)

                        DashboardView(workspace: workspace)
                            .opacity(selectedTab == .dashboard ? 1 : 0)
                            .allowsHitTesting(selectedTab == .dashboard)
                            .accessibilityHidden(selectedTab != .dashboard)

                        HabitTrackerView(store: habits, today: workspace.today)
                            .opacity(selectedTab == .habits ? 1 : 0)
                            .allowsHitTesting(selectedTab == .habits)
                            .accessibilityHidden(selectedTab != .habits)

                        StatsView(workspace: workspace, tasks: tasks, habits: habits, preferences: preferences, isVisible: selectedTab == .stats && !zen.isPresented)
                            .opacity(selectedTab == .stats ? 1 : 0)
                            .allowsHitTesting(selectedTab == .stats)
                            .accessibilityHidden(selectedTab != .stats)

                        KeepScrollView {
                            SettingsView(preferences: preferences, player: music, wallpapers: wallpapers, loginItem: loginItem, updater: updater, isVisible: selectedTab == .settings)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .opacity(selectedTab == .settings ? 1 : 0)
                        .allowsHitTesting(selectedTab == .settings)
                        .accessibilityHidden(selectedTab != .settings)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.musicLibraryViewport, geometry.size)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(KeepTheme.artworkSurface(KeepTheme.paper,
                    tint: wallpapers.palette(for: preferences.wallpaperSource)?.ambient.color,
                    amount: environment.colorScheme == .dark ? 0.16 : 0.10,
                    text: KeepTheme.mutedInk, environment: environment), in: RoundedRectangle(cornerRadius: 28))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(KeepTheme.border.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(16)
                .background { ArtworkBackdrop(preferences: preferences, wallpapers: wallpapers) }
                .opacity(zen.isPresented ? 0 : 1)
                .allowsHitTesting(!zen.isPresented)
                .accessibilityHidden(zen.isPresented)
                if zen.isPresented {
                    ZenModeView(workspace: workspace, music: music, preferences: preferences, wallpapers: wallpapers, onExit: { zen.exit() })
                }
            }
        }
        .background { ZenWindowBridge(model: zen).frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true) }
        .frame(minWidth: 680, minHeight: 650)
        .environment(\.artworkPalette, wallpapers.palette(for: preferences.wallpaperSource))
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .keepAppearance(preferences.appearance)
        .onChange(of: preferences.snapshot.wallpaperConfiguration, initial: true) { _, configuration in
            wallpapers.configure(configuration, preferences: preferences)
        }
        .onChange(of: music.track?.artworkURL, initial: true) { _, url in
            wallpapers.setArtwork(url: url, data: music.appleArtwork)
        }
        .onChange(of: music.appleArtwork) { _, data in
            wallpapers.setArtwork(url: music.track?.artworkURL, data: data)
        }
        .onAppear { workspace.startUpdating() }
    }
}

#Preview("Focus") {
    AppShellView().frame(width: 1000, height: 900)
}

#Preview("Dashboard") {
    AppShellView(initialTab: .dashboard, workspace: TimesheetPreviewData.workspace()).frame(width: 1000, height: 900)
}

#Preview("Wide window") {
    AppShellView().frame(width: 1710, height: 1080)
}

#Preview("Settings") {
    AppShellView(initialTab: .settings).frame(width: 1000, height: 900)
}
