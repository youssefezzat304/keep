import SwiftUI

struct ZenModeView: View {
    let workspace: WorkspaceModel
    let music: MusicPlayerModel
    let preferences: AppPreferences
    let wallpapers: WallpaperLibrary
    let onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                MusicArtworkView(preferences: preferences, wallpapers: wallpapers)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: onExit)
                VStack {
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
            .coordinateSpace(name: "zenArtwork")
            .environment(\.musicLibraryViewport, geometry.size)
        }
        .foregroundStyle(.white)
        .onExitCommand(perform: onExit)
        .accessibilityAction(named: "Previous wallpaper") { wallpapers.previous() }
        .accessibilityAction(named: "Next wallpaper") { wallpapers.next() }
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
