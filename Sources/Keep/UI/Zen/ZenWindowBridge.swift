import AppKit
import SwiftUI

/// Observe the owning window without replacing SwiftUI's window delegate.
struct ZenWindowBridge: NSViewRepresentable {
    let model: ZenModeModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WindowReader {
        let view = WindowReader()
        view.onWindowChange = { [weak coordinator = context.coordinator] in coordinator?.connect($0) }
        return view
    }

    func updateNSView(_ view: WindowReader, context: Context) {
        context.coordinator.connect(view.window)
    }

    static func dismantleNSView(_ view: WindowReader, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.connect(nil)
    }

    final class WindowReader: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindowChange?(window) }
    }

    final class Coordinator: ZenWindow {
        let model: ZenModeModel
        weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var keyMonitor: Any?
        init(model: ZenModeModel) { self.model = model }
        var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) == true }
        func toggleFullScreen() {
            guard let window else { return }
            if !window.collectionBehavior.contains(.fullScreenPrimary) && !window.collectionBehavior.contains(.fullScreenAuxiliary) {
                window.collectionBehavior.insert(.fullScreenPrimary)
            }
            window.toggleFullScreen(nil)
        }

        func connect(_ next: NSWindow?) {
            // A weak window may already be nil when SwiftUI dismantles the reader.
            guard next == nil || window !== next else { return }
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            model.detach()
            window = next
            guard let next else { return }
            model.attach(self)
            observe(NSWindow.didEnterFullScreenNotification, window: next) { $0.didEnterFullScreen() }
            observe(NSWindow.willExitFullScreenNotification, window: next) { $0.willExitFullScreen() }
            observe(NSWindow.didExitFullScreenNotification, window: next) { $0.didExitFullScreen() }
            observe(NSWindow.willCloseNotification, window: next) { $0.detach() }
            // SwiftUI's exit command depends on the responder's focus. Zen must also
            // exit when a timer, slider, saved row or the hidden shell has focus.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handleKeyDown(event) == nil
                }
                return consumed ? nil : event
            }
        }

        func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard event.type == .keyDown, event.keyCode == 53,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  event.window === window, model.isPresented else { return event }
            model.exit()
            return nil
        }

        private func observe(_ name: Notification.Name, window: NSWindow, action: @escaping @MainActor (ZenModeModel) -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, notification.object as? NSWindow === self.window else { return }
                    action(self.model)
                }
            })
        }
    }
}
