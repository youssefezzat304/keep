import AppKit
import SwiftUI

/// Modified shortcuts work throughout the active workspace, including text editors.
struct WallpaperShortcutBridge: NSViewRepresentable {
    let enabled: Bool
    let onMove: (Int) -> Void
    func makeNSView(context: Context) -> WallpaperShortcutView { WallpaperShortcutView() }
    func updateNSView(_ view: WallpaperShortcutView, context: Context) {
        view.enabled = enabled; view.onMove = onMove
    }
    static func dismantleNSView(_ view: WallpaperShortcutView, coordinator: ()) { view.detach() }
}

final class WallpaperShortcutView: NSView {
    var enabled = false
    var onMove: (Int) -> Void = { _ in }
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.filterEvent(event)
        }
    }
    /// Preserve the consumed result across the native callback's actor boundary.
    nonisolated func filterEvent(_ event: NSEvent) -> NSEvent? {
        let consumed = MainActor.assumeIsolated { handle(event) == nil }
        return consumed ? nil : event
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard enabled, event.type == .keyDown,
              event.keyCode == 123 || event.keyCode == 124,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command, .option],
              let window, event.window === window, window.attachedSheet == nil else { return event }
        if !event.isARepeat { onMove(event.keyCode == 123 ? -1 : 1) }
        return nil
    }
    func detach() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
