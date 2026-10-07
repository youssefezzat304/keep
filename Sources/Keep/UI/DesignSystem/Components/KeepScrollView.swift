import AppKit
import SwiftUI

/// Shared native overlay scrollbars, with a slim thumb and no track background.
struct KeepScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let content: Content

    init(_ axes: Axis.Set = .vertical, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    var body: some View {
        ScrollView(axes) {
            content.background { ScrollbarAppearance().allowsHitTesting(false) }
        }
    }
}

private struct ScrollbarAppearance: NSViewRepresentable {
    @Environment(\.self) private var environment
    func makeNSView(context: Context) -> ScrollbarProbe { ScrollbarProbe() }
    func updateNSView(_ view: ScrollbarProbe, context: Context) {
        view.thumbColor = NSColor(Color(KeepTheme.mutedInk.resolve(in: environment)))
        view.scheduleUpdate()
    }
}

private final class ScrollbarProbe: NSView {
    var thumbColor = NSColor.secondaryLabelColor
    private var updatePending = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleUpdate() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleUpdate() }

    func scheduleUpdate() {
        guard !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePending = false
            guard let scroll = self.enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.drawsBackground = false
            scroll.autohidesScrollers = true
            if let current = scroll.verticalScroller {
                let scroller = current as? KeepScroller ?? KeepScroller(frame: current.frame)
                if scroller !== current { scroll.verticalScroller = scroller }
                scroller.thumbColor = self.thumbColor
                scroller.controlSize = .small
                scroller.needsDisplay = true
            }
            if let current = scroll.horizontalScroller {
                let scroller = current as? KeepScroller ?? KeepScroller(frame: current.frame)
                if scroller !== current { scroll.horizontalScroller = scroller }
                scroller.thumbColor = self.thumbColor
                scroller.controlSize = .small
                scroller.needsDisplay = true
            }
        }
    }
}

private final class KeepScroller: NSScroller {
    var thumbColor = NSColor.secondaryLabelColor
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let rect = rect(for: .knob)
        guard !rect.isEmpty else { return }
        let vertical = bounds.height > bounds.width
        let thumb = vertical
            ? NSRect(x: rect.midX - 2.5, y: rect.minY, width: 5, height: rect.height)
            : NSRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)
        thumbColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 2.5, yRadius: 2.5).fill()
    }
}
