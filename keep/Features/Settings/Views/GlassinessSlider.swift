import AppKit
import SwiftUI

/// Keep AppKit's continuous pointer tracking stable while the artwork preview updates.
struct GlassinessSlider: NSViewRepresentable {
    @Binding var value: Double

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 1,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.cell = GrabbableSliderCell()
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = value
        slider.isContinuous = true
        slider.setAccessibilityLabel("Music card glassiness")
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.isEnabled = context.environment.isEnabled
        let fill = NSColor(Color(KeepTheme.accentStrong.resolve(in: context.environment)))
        slider.trackFillColor = fill
        (slider.cell as? GrabbableSliderCell)?.fillColor = fill
        slider.needsDisplay = true
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

/// A larger native tracking rectangle and thumb; AppKit still owns dragging/keyboard input.
private final class GrabbableSliderCell: NSSliderCell {
    var fillColor = NSColor.controlAccentColor
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let fraction = min(1, max(0, (doubleValue - minValue) / (maxValue - minValue)))
        let filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
        fillColor.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        NSBezierPath(roundedRect: filled, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
    override func knobRect(flipped: Bool) -> NSRect {
        let native = super.knobRect(flipped: flipped)
        let bounds = controlView?.bounds ?? .zero
        let center = min(max(native.midX, 14), max(14, bounds.width - 14))
        return NSRect(x: center - 14, y: native.midY - 14, width: 28, height: 28)
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        (isEnabled ? NSColor(calibratedWhite: 0.96, alpha: 1) : NSColor.disabledControlTextColor).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}
