import SwiftUI

enum WorkspaceCardPresentation { case standard, zen }

/// A warm readability wash over native material; Reduce Transparency uses solid paper.
struct ZenGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                if reduceTransparency {
                    shape.fill(KeepTheme.paper)
                } else {
                    shape.fill(.regularMaterial)
                        .overlay { shape.fill(KeepTheme.paper.opacity(colorScheme == .dark ? 0.65 : 0.55)) }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                    .strokeBorder(KeepTheme.border.opacity(0.6), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

