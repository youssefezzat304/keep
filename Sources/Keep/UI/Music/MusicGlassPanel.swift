import SwiftUI

/// Samples the artwork at the controls' actual position, rather than the window's material backdrop.
struct MusicGlassPanel: ViewModifier {
    var preferences: AppPreferences
    var wallpapers: WallpaperLibrary
    var artworkSize: CGSize
    var inset: CGFloat = 16
    var artworkCoordinateSpace: String? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || preferences.glassiness == 0 {
            content.background(KeepTheme.paper, in: shape)
                .overlay { shape.strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
        } else {
            content
                .background {
                    GeometryReader { panel in
                        let origin = artworkCoordinateSpace.map { panel.frame(in: .named($0)).origin }
                            ?? CGPoint(x: inset, y: artworkSize.height - panel.size.height - inset)
                        MusicArtworkView(preferences: preferences, wallpapers: wallpapers)
                            .frame(width: artworkSize.width, height: artworkSize.height)
                            .offset(x: -origin.x, y: -origin.y)
                            .blur(radius: 24 * (1 - preferences.glassiness), opaque: true)
                            .frame(width: panel.size.width, height: panel.size.height, alignment: .topLeading)
                            .overlay {
                                KeepTheme.paper.opacity(1 - preferences.glassiness)
                            }
                            .overlay {
                                LinearGradient(colors: [KeepTheme.paper.opacity(colorScheme == .dark ? 0.55 : 0.12),
                                                        KeepTheme.paper.opacity(colorScheme == .dark ? 0.68 : 0.3)],
                                               startPoint: .top, endPoint: .bottom)
                            }
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .modifier(MusicGlassFinish(isLiquid: preferences.glassStyle == .liquid, shape: shape))
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 17) }
}

private struct MusicGlassFinish: ViewModifier {
    let isLiquid: Bool
    let shape: RoundedRectangle

    @ViewBuilder func body(content: Content) -> some View {
        if isLiquid {
            // The clear variant keeps the explicitly aligned artwork visible.
            content.glassEffect(.clear, in: shape)
        } else {
            content.overlay { shape.strokeBorder(KeepTheme.paper.opacity(0.65), lineWidth: 1).allowsHitTesting(false) }
        }
    }
}
