import SwiftUI

/// Shared geometry and intensity colors for both annual activity grids.
enum ActivityGridStyle {
    static let spacing: CGFloat = 20
    static let tileSpacing: CGFloat = 3
    static let monthSpacing: CGFloat = 7

    static func tileSize(availableWidth: CGFloat, columns: Int) -> CGFloat {
        max(6, min(11, (availableWidth - CGFloat(max(0, columns - 1)) * tileSpacing) / CGFloat(max(1, columns))))
    }

    static func fill(level: Int, ink: Color) -> Color {
        level == 0 ? KeepTheme.mutedWarm : ink.opacity([0, 0.3, 0.5, 0.75, 1][min(4, max(0, level))])
    }
}

struct ActivitySquareButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay {
            RoundedRectangle(cornerRadius: 2).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
