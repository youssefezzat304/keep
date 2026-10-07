import SwiftUI

struct ArtworkBackdrop: View {
    var preferences: AppPreferences
    var wallpapers: WallpaperLibrary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                KeepTheme.background
                if let image = wallpapers.backdrop(for: preferences.wallpaperSource) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                }
            }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay {
                    if colorScheme == .dark { KeepTheme.background.opacity(0.55) }
                    else { KeepTheme.paper.opacity(0.18) }
                }
                .clipped()
        }
        .background(KeepTheme.background)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
