import AppKit
import SwiftUI

/// Isolated native timer layouts; KEEP_PROGRESS_INTERACTIVE=1 opens a disposable window.
@main enum PomodoroProgressPresentationChecks {
    static var renders = 0
    static func main() {
        let app = NSApplication.shared
        let runner = ProgressPresentationRunner()
        app.delegate = runner
        app.run()
        withExtendedLifetime(runner) {}
    }

    static func run() async throws {
        let output = URL(fileURLWithPath: "/tmp/keep-progress-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                for state in ["idle", "quarter", "half", "complete", "short-break", "long-break", "reset"] {
                    let timer = fixture(state)
                    let root = VStack {
                        if size.width < 820 {
                            card(timer)
                            card(FocusTimer(mode: .flow))
                        } else {
                            HStack(alignment: .top, spacing: 18) {
                                card(timer)
                                card(FocusTimer(mode: .flow))
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(24).frame(width: size.width, height: size.height)
                        .background(KeepTheme.paper).keepAppearance(appearance)
                    try await render(root, size: size, to: output.appendingPathComponent("\(state)-\(label)-\(appearance.rawValue).png"))
                }
            }
        }
        print("Rendered \(renders) native progress layouts: idle, partial, completed, short/long breaks and reset. Output: \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_PROGRESS_INTERACTIVE"] == "1" {
            let workspace = WorkspaceModel(focusDuration: 20, breakDuration: 10)
            workspace.startUpdating()
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Keep — isolated timer progress fixture"
            window.contentView = NSHostingView(rootView: ProgressInteractiveFixture(workspace: workspace, window: window))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(90))
            window.close()
            workspace.shutdown()
        }
    }

    static func fixture(_ state: String) -> FocusTimer {
        var timer = FocusTimer(mode: .pomodoro, focusDuration: 120, breakDuration: 60, longBreakDuration: 180,
            iterationsBeforeLongBreak: state == "long-break" ? 1 : 4)
        let origin = ContinuousClock.now.advanced(by: .seconds(-1000))
        if state == "idle" { return timer }
        timer.play(at: origin)
        switch state {
        case "quarter", "reset": timer.stop(at: origin.advanced(by: .seconds(30)))
        case "half": timer.stop(at: origin.advanced(by: .seconds(60)))
        case "complete": timer.settleCompletion(at: origin.advanced(by: .seconds(120)))
        default:
            timer.startBreak(at: origin.advanced(by: .seconds(120)))
            timer.stop(at: origin.advanced(by: .seconds(state == "long-break" ? 165 : 150)))
        }
        if state == "reset" { timer.reset() }
        return timer
    }

    static func card(_ timer: FocusTimer) -> some View {
        FocusTimerCard(timer: timer, onPlay: {}, onStop: {}, onReset: {}, onBreak: {}, onSettings: { _ in true })
    }

    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size, "The progress overlay must not change the viewport")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url)
        window.close()
        renders += 1
    }
}

private final class ProgressPresentationRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await PomodoroProgressPresentationChecks.run() }
            catch { preconditionFailure("Timer progress presentation failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}

private struct ProgressInteractiveFixture: View {
    let workspace: WorkspaceModel
    let window: NSWindow
    @State private var appearance: AppAppearance = .light
    @State private var compact = false
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Light") { appearance = .light }
                Button("Dark") { appearance = .dark }
                Button("Default") { compact = false; window.setContentSize(NSSize(width: 1000, height: 900)) }
                Button("Narrow") { compact = true; window.setContentSize(NSSize(width: 680, height: 650)) }
            }
            TimerWorkspaceCard(workspace: workspace, isCompact: compact)
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeepTheme.paper).keepAppearance(appearance)
    }
}
