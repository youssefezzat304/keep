import SwiftUI

extension FocusProject {
    var accentColor: Color { accent.color }
}

extension FocusProject.Accent {
    var color: Color {
        switch self {
        case .neutral: KeepTheme.mutedInk
        case .terracotta: KeepTheme.accent
        case .sage: KeepTheme.sage
        case .mistBlue: KeepTheme.mistBlue
        case .butter: KeepTheme.highlight
        default: Color("Project\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())")
        }
    }
}
