import AppKit
import SwiftUI

/// Keep AppKit's continuous pointer tracking stable while the artwork preview updates.
struct GlassinessSlider: NSViewRepresentable {
    @Binding var value: Double

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel("Music card glassiness")
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.isEnabled = context.environment.isEnabled
        slider.trackFillColor = NSColor(Color(KeepTheme.accentStrong.resolve(in: context.environment)))
        // Avoid writing the thumb's value back during its own continuous tracking action.
        if abs(slider.doubleValue - value) > 0.0001 { slider.doubleValue = value }
        slider.setAccessibilityValueDescription("\(Int(value * 100)) percent")
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ slider: NSSlider) { value.wrappedValue = slider.doubleValue }
    }
}
