import SwiftUI

/// Both presentations consume the same app-owned image and the same bundled fallback.
struct MusicArtworkView: View {
    var preferences: AppPreferences
    var wallpapers: WallpaperLibrary

    var body: some View {
        GeometryReader { geometry in
            artwork.resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }

    private var artwork: Image {
        if preferences.wallpaperSource != .cozy, let image = wallpapers.image { Image(nsImage: image) }
        else { Image("CozyCorner") }
    }
}
