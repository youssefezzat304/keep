import AppKit
import SwiftUI

/// Native timer preferences and reminder controls; optional disposable interactive window.
@main enum TimerSettingsPresentationChecks {
    static var renders = 0
    static func main() {
        let app = NSApplication.shared
        let runner = TimerSettingsPresentationRunner()
        app.delegate = runner
        app.run()
        withExtendedLifetime(runner) {}
    }

    static func run() async throws {
        let output = URL(fileURLWithPath: "/tmp/keep-timer-settings-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let preferences = AppPreferences()
        _ = preferences.setFlowReminder(minutes: 60)
        let sounds = TimerSoundPlayer()
        let workspace = WorkspaceModel(timerPreferences: preferences)
        let origin = ContinuousClock.now.advanced(by: .seconds(-600))
        workspace.startBothTimers(at: origin)
        workspace.stop(.pomodoro, at: origin.advanced(by: .seconds(600)))
        workspace.stop(.flow, at: origin.advanced(by: .seconds(600)))
        for appearance in [AppAppearance.light, .dark] {
            for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650))] {
                let settings = KeepScrollView {
                    settingsCard(preferences)
                }.padding(24).frame(width: size.width, height: size.height)
                    .background(KeepTheme.paper).keepAppearance(appearance).environment(sounds)
                try await render(settings, size: size, to: output.appendingPathComponent("settings-\(label)-\(appearance.rawValue).png"))
                for (state, showPomodoro, showFlow) in [("both", true, true), ("pomodoro", true, false), ("flow", false, true), ("none", false, false)] {
                    preferences.showPomodoroTimer = showPomodoro
                    preferences.showFlowTimer = showFlow
                    let timers = VStack {
                        TimerWorkspaceCard(workspace: workspace, isCompact: size.width < 820, preferences: preferences)
                        Spacer(minLength: 0)
                    }.padding(24).frame(width: size.width, height: size.height)
                        .background(KeepTheme.paper).keepAppearance(appearance)
                    try await render(timers, size: size, to: output.appendingPathComponent("timers-\(state)-\(label)-\(appearance.rawValue).png"))
                }
                preferences.showPomodoroTimer = true
                preferences.showFlowTimer = true
                preferences.showPomodoroProgress = true
            }
            for enabled in [true, false] {
                let size = NSSize(width: 400, height: 420)
                let popover = VStack {
                    FlowReminderPopover(minutes: enabled ? 60 : nil) { _ in true }
                    Spacer(minLength: 0)
                }.frame(width: size.width, height: size.height)
                    .background(KeepTheme.paper).keepAppearance(appearance)
                try await render(popover, size: size, to: output.appendingPathComponent("reminder-\(enabled ? "on" : "off")-\(appearance.rawValue).png"))
            }
        }
        print("Rendered \(renders) native timer settings, visibility and reminder layouts. Output: \(output.path)")
        if ProcessInfo.processInfo.environment["KEEP_TIMER_SETTINGS_INTERACTIVE"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 1000, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "Keep — isolated timer settings fixture"
            window.contentView = NSHostingView(rootView: TimerSettingsInteractiveFixture(workspace: workspace, preferences: preferences, window: window).environment(sounds))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(100))
            window.close()
        }
        workspace.shutdown()
        sounds.stop()
    }

    static func settingsCard(_ preferences: AppPreferences) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Timers", systemImage: "timer").font(KeepTheme.headingFont(size: 23))
            TimerSettingsControls(preferences: preferences)
        }.padding(22).frame(maxWidth: 900, alignment: .leading)
            .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
            .foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
    }

    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        precondition(host.bounds.size == size, "Preferences must preserve the viewport")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url)
        window.close()
        renders += 1
    }
}

private final class TimerSettingsPresentationRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await TimerSettingsPresentationChecks.run() }
            catch { preconditionFailure("Timer settings presentation failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}

private struct TimerSettingsInteractiveFixture: View {
    let workspace: WorkspaceModel
    let preferences: AppPreferences
    let window: NSWindow
    @State private var appearance: AppAppearance = .light
    @State private var compact = false
    @State private var settings = false
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Light") { appearance = .light }
                Button("Dark") { appearance = .dark }
                Button("Default") { compact = false; window.setContentSize(NSSize(width: 1000, height: 900)) }
                Button("Narrow") { compact = true; window.setContentSize(NSSize(width: 680, height: 650)) }
                Button(settings ? "Timers" : "Settings") { settings.toggle() }
            }
            ScrollView {
                if settings { TimerSettingsPresentationChecks.settingsCard(preferences) }
                else { TimerWorkspaceCard(workspace: workspace, isCompact: compact, preferences: preferences) }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeepTheme.paper).keepAppearance(appearance)
    }
}
