import SwiftUI

extension HabitIcon {
    var accent: FocusProject.Accent {
        switch self {
        case .checkmark: .seafoam
        case .book: .honey
        case .exercise: .lavender
        case .walk: .fern
        case .water: .teal
        case .leaf: .eucalyptus
        case .sleep: .plum
        case .music: .periwinkle
        case .write: .denim
        case .study: .mauve
        case .heart: .rose
        case .sun: .ochre
        }
    }
    func ink(in environment: EnvironmentValues) -> Color {
        HabitVisualStyle.ink(accent, in: environment)
    }
}

enum HabitVisualStyle {
    static func ink(_ accent: FocusProject.Accent, in environment: EnvironmentValues) -> Color {
        KeepTheme.readableAccent(accent.color, on: [KeepTheme.paper, KeepTheme.surface], environment: environment)
    }
    static func divider(vertical: Bool = false) -> some View {
        LinearGradient(colors: [.clear, KeepTheme.border.opacity(0.8), .clear],
                       startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
            .allowsHitTesting(false)
    }
}
