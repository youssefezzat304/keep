import AppKit
import SwiftUI

@MainActor private final class TestZenWindow: ZenWindow {
    var isFullScreen = false
    var toggles = 0
    func toggleFullScreen() { toggles += 1 }
}

/// Exercise AppKit attachment/notifications without displaying a window or changing Spaces.
private final class NativeZenWindow: NSWindow {
    var toggles = 0
    override func toggleFullScreen(_ sender: Any?) { toggles += 1 }
}

private final class ExistingWindowDelegate: NSObject, NSWindowDelegate {}

@main enum ZenModeChecks {
    private static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    static func main() async throws {
        let mode = ZenModeModel()
        mode.enter()
        expect(mode.phase == .inactive, "Do not enter without an owning window")
        let window = TestZenWindow()
        mode.attach(window)
        mode.enter()
        expect(mode.phase == .entering && mode.isPresented, "Show wallpaper during native entry")
        expect(window.toggles == 1, "Enter native full screen once")
        mode.enter()
        expect(window.toggles == 1, "Ignore repeated entry")
        window.isFullScreen = true
        mode.didEnterFullScreen()
        expect(mode.phase == .active, "Finish native entry")
        mode.exit()
        expect(mode.phase == .leaving && !mode.isPresented, "Restore workspace on Exit")
        expect(window.toggles == 2, "Restore the original window mode")
        mode.exit()
        expect(window.toggles == 2, "Ignore repeated exit")
        window.isFullScreen = false
        mode.didExitFullScreen()
        expect(mode.phase == .inactive, "Finish native exit")

        window.isFullScreen = true
        mode.enter()
        expect(mode.phase == .active, "Already full-screen windows enter Zen directly")
        expect(window.toggles == 2, "Keep existing full screen")
        mode.exit()
        expect(mode.phase == .inactive && window.toggles == 2, "Exit Zen preserves pre-existing full screen")

        window.isFullScreen = false
        mode.enter()
        mode.exit()
        expect(mode.phase == .leaving && window.toggles == 3, "Escape during entry waits for AppKit")
        window.isFullScreen = true
        mode.didEnterFullScreen()
        expect(window.toggles == 4, "Exit immediately after pending entry finishes")
        window.isFullScreen = false
        mode.didExitFullScreen()
        expect(mode.phase == .inactive, "Rapid Escape returns to normal")

        mode.enter()
        window.isFullScreen = true
        mode.didEnterFullScreen()
        mode.willExitFullScreen()
        expect(!mode.isPresented, "Native full-screen exit also leaves Zen")
        window.isFullScreen = false
        mode.didExitFullScreen()
        expect(mode.phase == .inactive && window.toggles == 5, "Native exit never toggles the window again")

        let second = ZenModeModel()
        let secondWindow = TestZenWindow()
        second.attach(secondWindow)
        second.enter()
        expect(mode.phase == .inactive && second.isPresented, "Zen presentation stays window-local")
        second.detach()
        expect(second.phase == .inactive, "Closing or detaching clears transition state")
        second.didEnterFullScreen()
        expect(secondWindow.toggles == 1, "Late window callbacks cannot trigger another transition")
        second.enter()
        expect(!second.isPresented, "Detached windows cannot re-enter")

        _ = NSApplication.shared
        let nativeMode = ZenModeModel()
        let native = NativeZenWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        native.isReleasedWhenClosed = false
        let delegate = ExistingWindowDelegate()
        native.delegate = delegate
        let host = NSHostingView(rootView: ZenWindowBridge(model: nativeMode).frame(width: 0, height: 0))
        native.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        nativeMode.enter()
        expect(native.toggles == 1, "The zero-size bridge attaches to the actual owning window")
        expect(native.collectionBehavior.contains(.fullScreenPrimary), "Native entry enables full-screen capability")
        expect(native.delegate === delegate, "Preserve the window's existing delegate")
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: NSObject())
        expect(nativeMode.phase == .entering, "Ignore another window's notifications")
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: native)
        expect(nativeMode.phase == .active, "Native entry notification activates Zen")
        nativeMode.exit()
        expect(native.toggles == 2, "Exit routes through the owning native window")
        NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: native)
        expect(!nativeMode.isPresented, "Native exit hides Zen")
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: native)
        expect(nativeMode.phase == .inactive, "Native exit resets the transition")
        nativeMode.enter()
        native.close()
        expect(nativeMode.phase == .inactive, "Native window closure clears Zen")
        nativeMode.enter()
        expect(native.toggles == 3, "Closed windows cannot receive another full-screen request")
        native.contentView = nil
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: native)
        expect(nativeMode.phase == .inactive, "Detached native callbacks cannot reopen Zen")
        print("Passed \(checks) Zen mode checks")
    }
}
