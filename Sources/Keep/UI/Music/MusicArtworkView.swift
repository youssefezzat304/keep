import SwiftUI

/// Shares selected media and its prepared poster/fallback; native video never owns selection.
struct MusicArtworkView: View {
    var preferences: AppPreferences
    var wallpapers: WallpaperLibrary
    var animates = true
    @State private var isOnscreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                artwork.resizable().scaledToFill()
                if animates, isOnscreen, !reduceMotion, preferences.wallpaperSource == .folder, let video = wallpapers.video {
                    WallpaperVideoView(video: video) { wallpapers.videoFailed($0) }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .onScrollVisibilityChange(threshold: 0.01) { isOnscreen = $0 }
        .accessibilityHidden(true)
    }

    private var artwork: Image {
        if preferences.wallpaperSource != .cozy, let image = wallpapers.image { Image(nsImage: image) }
        else { Image("CozyCorner") }
    }
}
