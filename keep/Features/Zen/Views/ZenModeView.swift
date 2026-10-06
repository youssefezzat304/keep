import SwiftUI

struct ZenModeView: View {
    let workspace: WorkspaceModel
    let music: MusicPlayerModel
    let preferences: AppPreferences
    let wallpapers: WallpaperLibrary
    let onExit: () -> Void
    @FocusState private var exitFocused: Bool
    @State private var exitHovered = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MusicArtworkView(preferences: preferences, wallpapers: wallpapers)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                KeepScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            Button(action: onExit) {
                                Label("Exit Zen", systemImage: "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .focused($exitFocused)
                            .onHover { exitHovered = $0 }
                            .modifier(ZenGlassSurface())
                            .overlay {
                                RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                                    .strokeBorder(exitFocused ? KeepTheme.focusRing : exitHovered ? KeepTheme.border : .clear, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                            .help("Exit Zen mode (Escape)")
                        }
                        Spacer(minLength: 0)
                        TimerWorkspaceCard(workspace: workspace, presentation: .zen)
                            .frame(maxWidth: 820)
                        MusicPlayerCard(player: music, preferences: preferences, wallpapers: wallpapers, presentation: .zen)
                            .frame(maxWidth: 820)
                            .frame(height: 270)
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            .environment(\.musicLibraryViewport, geometry.size)
        }
        .foregroundStyle(KeepTheme.ink)
        .onAppear { exitFocused = true }
        .onExitCommand(perform: onExit)
    }
}
