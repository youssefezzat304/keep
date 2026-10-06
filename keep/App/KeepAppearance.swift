import AppKit
import Observation
import SwiftUI

/// Read the application appearance, independently of a window's explicit override.
@Observable
final class SystemAppearance {
    private(set) var colorScheme: ColorScheme
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(application: NSApplication = .shared) {
        colorScheme = Self.scheme(for: application.effectiveAppearance)
        observation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] application, _ in
            Task { @MainActor [weak self] in
                self?.colorScheme = Self.scheme(for: application.effectiveAppearance)
            }
        }
    }

    private static func scheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

private struct KeepAppearance: ViewModifier {
    let appearance: AppAppearance
    @State private var system = SystemAppearance()

    func body(content: Content) -> some View {
        // Returning nil after an explicit override can leave macOS SwiftUI content stale.
        content.preferredColorScheme(appearance.colorScheme ?? system.colorScheme)
    }
}

extension View {
    func keepAppearance(_ appearance: AppAppearance) -> some View {
        modifier(KeepAppearance(appearance: appearance))
    }
}
