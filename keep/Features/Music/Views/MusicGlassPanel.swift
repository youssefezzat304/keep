import SwiftUI

struct MusicGlassPanel: ViewModifier {
    var preferences: AppPreferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || preferences.glassiness == 0 {
            content.background(KeepTheme.paper, in: shape)
        } else if preferences.glassStyle == .liquid {
            content.glassEffect(
                (preferences.glassiness > 0.65 ? Glass.clear : Glass.regular)
                    .tint(KeepTheme.paper.opacity(1 - preferences.glassiness * 0.45)), in: shape)
        } else {
            content.background {
                shape.fill(material)
                    .overlay { shape.fill(KeepTheme.paper.opacity(0.9 - preferences.glassiness * 0.7)) }
            }
            .overlay { shape.strokeBorder(KeepTheme.border.opacity(0.7), lineWidth: 1) }
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 17) }
    private var material: Material {
        switch preferences.glassiness {
        case ..<0.25: .thickMaterial
        case ..<0.5: .regularMaterial
        case ..<0.75: .thinMaterial
        default: .ultraThinMaterial
        }
    }
}
