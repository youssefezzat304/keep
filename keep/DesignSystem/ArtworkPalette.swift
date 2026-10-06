import SwiftUI

/// Runtime artwork colors, shared with the shell and timers without changing saved theme assets.
struct ArtworkPalette: Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    }

    let ambient: RGB
    let primary: RGB
    let secondary: RGB
}

extension EnvironmentValues {
    @Entry var artworkPalette: ArtworkPalette? = nil
}

extension KeepTheme {
    /// Project fills can be pale in Light or deep in Dark; retain their hue in a readable ink shade.
    static func readableAccent(_ accent: Color, on backgrounds: [Color], environment: EnvironmentValues) -> Color {
        let original = accent.resolve(in: environment)
        let surfaces = backgrounds.map { $0.resolve(in: environment) }
        let r = Double(original.red), g = Double(original.green), b = Double(original.blue)
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        let lightness = (high + low) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if delta > 0 {
            if high == r { hue = (g - b) / delta }
            else if high == g { hue = 2 + (b - r) / delta }
            else { hue = 4 + (r - g) / delta }
            if hue < 0 { hue += 6 }
        }
        // Change lightness in HSL so deep/pastel project colors retain their own hue.
        let target = environment.colorScheme == .dark ? 1.0 : 0.0
        for step in 0...40 {
            let level = lightness + (target - lightness) * Double(step) / 40
            let chroma = (1 - abs(2 * level - 1)) * saturation
            let x = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
            let m = level - chroma / 2
            let rgb: (Double, Double, Double)
            switch hue {
            case ..<1: rgb = (chroma, x, 0)
            case ..<2: rgb = (x, chroma, 0)
            case ..<3: rgb = (0, chroma, x)
            case ..<4: rgb = (0, x, chroma)
            case ..<5: rgb = (x, 0, chroma)
            default: rgb = (chroma, 0, x)
            }
            let result = Color(.sRGB, red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m, opacity: 1).resolve(in: environment)
            if surfaces.allSatisfy({ contrast(result, $0) >= 4.5 }) { return Color(result) }
        }
        return self.ink
    }

    /// Keep opaque, appearance-aware surfaces and limit the tint before it weakens text contrast.
    static func artworkSurface(_ base: Color, tint: Color?, amount: Double,
                               text: Color = ink, environment: EnvironmentValues) -> Color {
        guard let tint else { return base }
        let original = base.resolve(in: environment)
        let sampled = tint.resolve(in: environment)
        let foreground = text.resolve(in: environment)
        var fraction = Float(amount)
        while fraction > 0.01 {
            var result = original
            result.linearRed += (sampled.linearRed - original.linearRed) * fraction
            result.linearGreen += (sampled.linearGreen - original.linearGreen) * fraction
            result.linearBlue += (sampled.linearBlue - original.linearBlue) * fraction
            if contrast(result, foreground) >= 4.5 { return Color(result) }
            fraction *= 0.8
        }
        return base
    }

    private static func contrast(_ a: Color.Resolved, _ b: Color.Resolved) -> Float {
        func luminance(_ color: Color.Resolved) -> Float {
            0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
