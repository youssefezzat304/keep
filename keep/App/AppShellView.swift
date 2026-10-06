import SwiftUI

enum WorkspaceTab {
    case focus
    case dashboard
    case habits
    case settings
}

struct AppShellView: View {
    @State private var workspace: WorkspaceModel
    @State private var music: MusicPlayerModel
    @State private var tasks: DailyTaskStore
    @State private var preferences: AppPreferences
    @State private var wallpapers: WallpaperLibrary
    @State private var selectedTab: WorkspaceTab
    @Environment(\.self) private var environment

    init(initialTab: WorkspaceTab = .focus, workspace: WorkspaceModel = WorkspaceModel(), music: MusicPlayerModel = MusicPlayerModel(), tasks: DailyTaskStore = DailyTaskStore(), preferences: AppPreferences = AppPreferences(), wallpapers: WallpaperLibrary = WallpaperLibrary()) {
        _workspace = State(initialValue: workspace)
        _music = State(initialValue: music)
        _tasks = State(initialValue: tasks)
        _preferences = State(initialValue: preferences)
        _wallpapers = State(initialValue: wallpapers)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 24) {
                NavBar(
                    selection: selectedTab,
                    onSelectFocus: { selectedTab = .focus },
                    onSelectDashboard: { selectedTab = .dashboard },
                    onSelectHabits: { selectedTab = .habits },
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
                            FocusSessionView(workspace: workspace, music: music, tasks: tasks, preferences: preferences, wallpapers: wallpapers, isCompact: geometry.size.width < 820, isActive: selectedTab == .focus, minimumHeight: viewport.size.height)
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

                    HabitTrackerView()
                        .opacity(selectedTab == .habits ? 1 : 0)
                        .allowsHitTesting(selectedTab == .habits)
                        .accessibilityHidden(selectedTab != .habits)

                    KeepScrollView {
                        SettingsView(preferences: preferences, player: music, wallpapers: wallpapers)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
                    .accessibilityHidden(selectedTab != .settings)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        }
        .frame(minWidth: 680, minHeight: 650)
        .environment(\.artworkPalette, wallpapers.palette(for: preferences.wallpaperSource))
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onChange(of: preferences.snapshot.wallpaperConfiguration, initial: true) { _, configuration in
            wallpapers.configure(configuration, preferences: preferences)
        }
        .onChange(of: music.track?.artworkURL, initial: true) { _, url in
            wallpapers.setArtworkURL(url)
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
