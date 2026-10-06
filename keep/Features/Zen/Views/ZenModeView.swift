import SwiftUI

struct ZenModeView: View {
    let workspace: WorkspaceModel
    let music: MusicPlayerModel
    let preferences: AppPreferences
    let wallpapers: WallpaperLibrary
    let onExit: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var exitFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                MusicArtworkView(preferences: preferences, wallpapers: wallpapers)
                    .ignoresSafeArea().allowsHitTesting(false)
                // Protect white controls over arbitrary wallpapers without adding cards.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(reduceTransparency ? 0.95 : 0.7), location: 0.4),
                    .init(color: .black.opacity(reduceTransparency ? 1 : 0.85), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.width < 800 ? 250 : 160)
                    .allowsHitTesting(false).accessibilityHidden(true)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onExit) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 32, height: 32)
                        }
                        .buttonStyle(ZenControlStyle()).focused($exitFocused)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Exit Zen mode").help("Exit Zen mode (Escape)")
                    }
                    Spacer(minLength: 24)
                    if geometry.size.width < 800 {
                        VStack(alignment: .leading, spacing: 22) {
                            timers.frame(maxWidth: .infinity, alignment: .trailing)
                            ZenMusicControls(player: music, preferences: preferences, wallpapers: wallpapers)
                        }
                    } else {
                        HStack(alignment: .bottom, spacing: 32) {
                            ZenMusicControls(player: music, preferences: preferences, wallpapers: wallpapers)
                                .frame(maxWidth: 420)
                            Spacer(minLength: 24)
                            timers
                        }
                    }
                }
                .padding(28)
            }
            .environment(\.musicLibraryViewport, geometry.size)
        }
        .foregroundStyle(.white)
        .onAppear { exitFocused = true }
        .onExitCommand(perform: onExit)
    }

    private var timers: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ZenTimerReadout(workspace: workspace, mode: .pomodoro)
            ZenTimerReadout(workspace: workspace, mode: .flow)
        }
    }
}

struct ZenControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            .background(.black.opacity(hovered || configuration.isPressed || focused ? 0.4 : 0), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? .white : .clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
            .contentShape(Rectangle()).onHover { hovered = $0 }
    }
}
