import AppKit
import SwiftUI

@main enum PomodoroOverlayChecks {
    static var checks = 0, renders = 0
    static func expect(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
    static func main() {
        let app = NSApplication.shared, runner = OverlayChecksRunner()
        app.delegate = runner; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(runner) {}
    }
    static func run() async throws {
        let suite = "keep.pomodoro-overlays.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults), options = AppPreferences(persistence: SettingsPersistence(defaults: defaults))
        expect(!options.notchPomodoroTimer && !options.notchPomodoroCompletion && !options.blurPomodoroBreaks && !options.repeatPomodoroSound, "All new visual and repeating-audio features are opt-in")
        expect(options.pomodoroSoundRepetition == .once, "Existing audio remains one play")
        options.notchPomodoroCompletion = true; options.blurPomodoroBreaks = true; options.repeatPomodoroSound = true
        expect(!options.notchPomodoroTimer && options.notchPomodoroCompletion, "Completion display is independent of the ongoing timer")
        expect(options.pomodoroSoundRepetition == .untilDismissed, "Indefinite repetition is available")
        options.pomodoroSoundRepeatMode = .count; options.pomodoroSoundRepeatCount = 4
        expect(options.pomodoroSoundRepetition == .count(4), "A fixed total number of plays is available")
        options.pomodoroSoundRepeatCount = 0; options.pomodoroSoundRepeatCount = 21
        expect(options.pomodoroSoundRepeatCount == 4, "Invalid repeat counts preserve the previous value")
        let reloaded = AppPreferences(persistence: persistence)
        expect(reloaded.snapshot == options.snapshot, "New settings survive local reload")
        let portable = try JSONDecoder().decode(PortableSettings.self, from: JSONEncoder().encode(PortableSettings(options.snapshot)))
        let portableSettings = portable.applying(to: SettingsArchive())
        expect(portableSettings == options.snapshot, "Portable backups retain independent settings and repeat mode/count")
        let fields = ["notchPomodoroTimer", "notchPomodoroCompletion", "blurPomodoroBreaks", "repeatPomodoroSound", "pomodoroSoundRepeatMode", "pomodoroSoundRepeatCount"]
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(options.snapshot)) as? [String: Any] ?? [:]
        for key in fields { legacy.removeValue(forKey: key) }
        let oldSettings = try JSONDecoder().decode(SettingsArchive.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(oldSettings.isValid && oldSettings.notchPomodoroTimer == nil && oldSettings.repeatPomodoroSound == nil, "Old settings retain opt-in defaults")
        var oldPortable = try JSONSerialization.jsonObject(with: JSONEncoder().encode(portable)) as? [String: Any] ?? [:]
        for key in fields { oldPortable.removeValue(forKey: key) }
        let restoredLegacy = try JSONDecoder().decode(PortableSettings.self, from: JSONSerialization.data(withJSONObject: oldPortable)).applying(to: options.snapshot)
        expect(restoredLegacy.isValid && restoredLegacy.blurPomodoroBreaks == nil && restoredLegacy.pomodoroSoundRepeatMode == nil, "Old backups clear unsupported preferences to their compatible defaults")
        var corrupt = options.snapshot; corrupt.pomodoroSoundRepeatCount = -1
        expect(!corrupt.isValid, "Corrupt stored counts fail validation")

        let clock = ContinuousClock.now, date = Date.now
        func at(_ seconds: Int) -> ContinuousClock.Instant { clock + .seconds(seconds) }
        func day(_ seconds: Int) -> Date { date.addingTimeInterval(Double(seconds)) }
        let workspace = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: date, timerPreferences: options)
        defer { workspace.shutdown(at: at(50), date: day(50)) }
        var events: [TimerSound] = []
        workspace.onTimerReminder = { events.append($0) }
        options.timerSoundsEnabled = false
        workspace.play(.pomodoro, at: at(0), date: day(0))
        workspace.stop(.pomodoro, at: at(4), date: day(4))
        workspace.synchronize(at: at(20), date: day(20))
        expect(workspace.pomodoroCompletion == nil, "Paused intervals cannot produce completion notices")
        workspace.play(.pomodoro, at: at(20), date: day(20))
        workspace.synchronize(at: at(26), date: day(26))
        let notice = workspace.pomodoroCompletion
        expect(notice?.isBreak == false && notice?.title == "Focus complete" && events.isEmpty, "Visual completion is independent of muted sound")
        workspace.synchronize(at: at(27), date: day(27))
        expect(workspace.pomodoroCompletion == notice, "Refreshes do not create duplicate completion events")
        workspace.dismissPomodoroCompletion()
        workspace.synchronize(at: at(28), date: day(28))
        expect(workspace.pomodoroCompletion == nil, "Dismissed completion does not replay")
        workspace.startBreak(at: at(28), date: day(28))
        expect(workspace.pomodoro.interval == .rest && workspace.pomodoroCompletion == nil, "Starting the next interval clears its completion")
        options.timerSoundsEnabled = true
        workspace.synchronize(at: at(33), date: day(33))
        expect(workspace.pomodoroCompletion?.isBreak == true && events == [.breakComplete], "Break completion has its own notice and one sound event")
        workspace.play(.pomodoro, at: at(33), date: day(33))
        expect(workspace.pomodoroCompletion == nil && workspace.pomodoro.interval == .focus, "Starting focus acknowledges completed break")
        workspace.synchronize(at: at(43), date: day(43))
        workspace.startBreak(at: at(43), date: day(43))
        workspace.play(.flow, at: at(43), date: day(43))
        let cycles = workspace.pomodoro.completedFocusIntervals
        workspace.skipPomodoroBreak(at: at(45), date: day(45))
        expect(workspace.pomodoro.interval == .focus && workspace.pomodoro.phase(at: at(45)) == .running, "Skip break starts a fresh focus interval")
        expect(workspace.pomodoro.completedFocusIntervals == cycles && workspace.flow.phase(at: at(45)) == .running, "Skip preserves focus cycle and independent Flow")
        expect(workspace.ledger.completedPomodoros.count == 2, "Skipped breaks never invent focus completions")
        expect(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } == 22, "Break overlay actions preserve the single-recorder priority")
        workspace.reset(.pomodoro, at: at(45), date: day(45))
        expect(workspace.pomodoroCompletion == nil, "Reset clears stale notices")
        workspace.installBackup(TimesheetLedger())
        expect(workspace.pomodoroCompletion == nil && workspace.pomodoro.phase(at: at(45)) == .idle, "Restore contains no live notice or overlay state")

        let nonNotch = PomodoroOverlayLayout(screen: CGRect(x: -1920, y: 200, width: 1920, height: 1080), topInset: 0, leftArea: .zero, rightArea: .zero, expanded: false)
        expect(nonNotch.cameraWidth == 0 && nonNotch.frame.midX == -960 && nonNotch.frame.maxY == 1280 && nonNotch.frame.height == 28, "Non-notched external displays use a compact panel at their own top center with negative screen coordinates")
        let notched = PomodoroOverlayLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32, leftArea: CGRect(x: 0, y: 950, width: 666, height: 32), rightArea: CGRect(x: 846, y: 950, width: 666, height: 32), expanded: false)
        expect(notched.cameraWidth == 180 && notched.frame.midX == 756 && notched.frame.maxY == 982 && notched.frame.height == 32, "Compact geometry reserves the camera housing without extending below its height")
        let expanded = PomodoroOverlayLayout(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32, leftArea: CGRect(x: 0, y: 950, width: 666, height: 32), rightArea: CGRect(x: 846, y: 950, width: 666, height: 32), expanded: true)
        expect(expanded.frame.height > notched.frame.height && expanded.topPadding == 32 && expanded.frame.maxY == notched.frame.maxY, "Completion expands below the camera while keeping its top anchor")

        // Native panels in an isolated check identity; no user's Keep data or timer is used.
        let nativeOptions = AppPreferences(), sounds = TimerSoundPlayer(), controller = PomodoroOverlayController()
        let native = WorkspaceModel(focusDuration: 10, breakDuration: 5, timerPreferences: nativeOptions)
        defer { controller.shutdown(); native.shutdown(at: at(30), date: day(30)); sounds.stop() }
        controller.start(workspace: native, preferences: nativeOptions, sounds: sounds)
        func panels(_ title: String) -> [NSWindow] { NSApp.windows.filter { $0.title == title && $0.isVisible } }
        native.play(.pomodoro, at: at(0), date: day(0))
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro").isEmpty, "Opt-out creates no overlay windows")
        nativeOptions.notchPomodoroTimer = true
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro").count == 1 && panels("Keep Pomodoro").first?.ignoresMouseEvents == true, "Compact panel is click-through and independent of open workspace windows")
        nativeOptions.notchPomodoroTimer = false; nativeOptions.notchPomodoroCompletion = true
        native.synchronize(at: at(10), date: day(10))
        try await Task.sleep(for: .milliseconds(400))
        expect(panels("Keep Pomodoro").count == 1 && (panels("Keep Pomodoro").first?.frame.height ?? 0) > 100, "Completion-only mode opens its expanded native panel")
        native.dismissPomodoroCompletion()
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro").isEmpty, "Acknowledgement closes completion-only panel")
        nativeOptions.blurPomodoroBreaks = true
        native.startBreak(at: at(10), date: day(10))
        try await Task.sleep(for: .milliseconds(150))
        expect(panels("Keep Pomodoro break").count == NSScreen.screens.count, "Running break covers each connected screen")
        expect(panels("Keep Pomodoro break").allSatisfy { panel in NSScreen.screens.contains { $0.frame == panel.frame } }, "Break panels match connected display frames")
        native.stop(.pomodoro, at: at(12), date: day(12))
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro break").isEmpty, "Pausing removes break screens without resetting the interval")
        native.play(.pomodoro, at: at(12), date: day(12))
        try await Task.sleep(for: .milliseconds(120))
        nativeOptions.blurPomodoroBreaks = false
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro break").isEmpty && native.pomodoro.phase(at: at(12)) == .running, "Disabling blur removes panels without changing timing")
        nativeOptions.notchPomodoroCompletion = false
        native.synchronize(at: at(15), date: day(15))
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro").isEmpty, "Disabled completion visuals stay off")

        nativeOptions.repeatPomodoroSound = true
        sounds.play(.breakComplete, repetition: .untilDismissed)
        native.play(.pomodoro, at: at(15), date: day(15))
        try await Task.sleep(for: .milliseconds(120))
        expect(!sounds.isRepeating, "Starting the next interval cancels outstanding repeated audio")
        native.onTimerReminder = { sound in sounds.play(sound, repetition: nativeOptions.pomodoroSoundRepetition) }
        native.synchronize(at: at(25), date: day(25))
        try await Task.sleep(for: .milliseconds(120))
        expect(sounds.isRepeating, "A new completion can arm its own repeated sound")
        nativeOptions.timerSoundsEnabled = false
        try await Task.sleep(for: .milliseconds(120))
        expect(!sounds.isRepeating && native.pomodoroCompletion != nil, "Muting stops audio without dismissing independent visual completion")
        nativeOptions.timerSoundsEnabled = true
        try await Task.sleep(for: .milliseconds(120))
        expect(!sounds.isRepeating, "Unmuting cannot replay the consumed completion")
        native.dismissPomodoroCompletion()
        controller.shutdown(); sounds.stop()

        let autoOptions = AppPreferences(), autoSounds = TimerSoundPlayer(), autoController = PomodoroOverlayController()
        autoOptions.blurPomodoroBreaks = true; autoOptions.notchPomodoroTimer = true
        autoOptions.notchPomodoroCompletion = true; autoOptions.repeatPomodoroSound = true
        let auto = WorkspaceModel(focusDuration: 10, breakDuration: 5, timerPreferences: autoOptions)
        defer { autoController.shutdown(); auto.shutdown(); autoSounds.stop() }
        auto.onTimerReminder = { autoSounds.play($0, repetition: autoOptions.pomodoroSoundRepetition) }
        autoController.start(workspace: auto, preferences: autoOptions, sounds: autoSounds)
        auto.play(.pomodoro, at: ContinuousClock.now - .seconds(10), date: Date.now.addingTimeInterval(-10))
        auto.synchronize()
        try await Task.sleep(for: .milliseconds(200))
        expect(panels("Keep Pomodoro break").count == NSScreen.screens.count && auto.pomodoro.interval == .rest, "Focus completion immediately presents native break screens without a notch action")
        expect(panels("Keep Pomodoro").count == 1 && (panels("Keep Pomodoro").first?.frame.height ?? 100) < 100, "Automatic breaks retain the compact notch instead of expanding its completion notice")
        expect(autoSounds.isRepeating && auto.pomodoroCompletion?.usesBreakScreen(timer: auto.pomodoro) == true, "Automatic transition keeps the focus sound available until acknowledgement")
        autoOptions.notchPomodoroTimer = false
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro").isEmpty && panels("Keep Pomodoro break").count == NSScreen.screens.count, "Completion-only notch settings cannot duplicate the break-screen notification")
        guard let host = panels("Keep Pomodoro break").first?.contentView as? NSHostingView<PomodoroBreakView> else { throw CocoaError(.coderInvalidValue) }
        host.rootView.dismiss()
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro break").isEmpty && !autoSounds.isRepeating && auto.pomodoroCompletion == nil, "The break view's dismiss action acknowledges audio and closes its screen panels")
        expect(auto.pomodoro.interval == .rest && auto.pomodoro.phase() == .running, "Dismissing the notifier keeps the automatic break counting")
        auto.synchronize()
        try await Task.sleep(for: .milliseconds(120))
        expect(panels("Keep Pomodoro break").isEmpty && panels("Keep Pomodoro").isEmpty, "A dismissed automatic notification cannot reopen on the next refresh")
        autoController.shutdown(); auto.shutdown(); autoSounds.stop()

        // Real audio exercises finite completion, indefinite repetition, cancellation and failure.
        sounds.play(.focusComplete, repetition: .count(2))
        expect(sounds.isRepeating, "Fixed sound count arms repetition")
        let audioDeadline = ContinuousClock.now + .seconds(15)
        while sounds.isPlaying && ContinuousClock.now < audioDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        expect(!sounds.isRepeating && !sounds.isPlaying && sounds.errorMessage == nil, "Two plays stop automatically after the first and one repeat")
        sounds.play(.breakComplete, repetition: .untilDismissed)
        try await Task.sleep(for: .seconds(5))
        expect(sounds.isRepeating && sounds.isPlaying, "Until-dismissed mode survives the first complete playback")
        sounds.stopRepeating()
        expect(!sounds.isRepeating, "Dismissal disarms looping immediately")
        sounds.stop()
        sounds.play(.focusComplete, repetition: .untilDismissed); sounds.stopRepeating()
        try await Task.sleep(for: .milliseconds(100))
        expect(!sounds.isRepeating, "Dismissal while loading cannot arm another repeat")
        sounds.stop()
        let emptyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keep-empty-sound-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: emptyURL, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: emptyURL) }
            catch { preconditionFailure("Could not remove the isolated audio fixture: \(error)") }
        }
        guard let empty = Bundle(url: emptyURL) else { throw CocoaError(.fileReadCorruptFile) }
        do {
            let failure = TimerSoundPlayer(bundle: empty); failure.play(.focusComplete, repetition: .untilDismissed)
            try await Task.sleep(for: .milliseconds(150))
            expect(!failure.isRepeating && failure.errorMessage != nil, "Missing audio stops repetition with an actionable error")
            failure.stop()
        }

        let output = URL(fileURLWithPath: "/tmp/keep-pomodoro-overlay-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var focus = FocusTimer(mode: .pomodoro, focusDuration: 180 * 60); focus.play(at: clock)
        for (name, layout) in [("notched", notched), ("plain", nonNotch)] {
            try await render(PomodoroTopView(timer: focus, instant: at(120), layout: layout, notice: nil, dismiss: {}, next: {}), size: layout.frame.size, to: output.appendingPathComponent("timer-\(name).png"))
        }
        try await render(PomodoroTopView(timer: focus, instant: clock, layout: expanded, notice: .init(intervalID: UUID(), isBreak: false), dismiss: {}, next: {}), size: expanded.frame.size, to: output.appendingPathComponent("completion.png"))
        var rest = FocusTimer(mode: .pomodoro, focusDuration: 10); rest.play(at: clock); rest.startBreak(at: at(10))
        for (label, size) in [("default", NSSize(width: 1000, height: 900)), ("narrow", NSSize(width: 680, height: 650)), ("wide", NSSize(width: 1710, height: 1080))] {
            try await render(PomodoroBreakView(timer: rest, instant: at(30), date: date, screenTopInset: 38, dismiss: {}, skip: {}), size: size, to: output.appendingPathComponent("break-\(label).png"))
            for appearance in [AppAppearance.light, .dark] {
                let settings = KeepScrollView { TimerSettingsControls(preferences: options).padding(24) }.frame(width: size.width, height: size.height).background(KeepTheme.paper).foregroundStyle(KeepTheme.ink).keepAppearance(appearance).environment(sounds)
                try await render(settings, size: size, to: output.appendingPathComponent("settings-\(label)-\(appearance.rawValue).png"))
            }
        }
        print("Passed \(checks) Pomodoro overlay, repetition, persistence and native panel checks; rendered \(renders) layouts in \(output.path)")
    }
    static func render<V: View>(_ root: V, size: NSSize, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root); host.sizingOptions = []
        window.contentView = host; window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(400)); host.layoutSubtreeIfNeeded()
        expect(host.bounds.size == size, "Overlay and settings retain requested native viewport")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        try png.write(to: url); window.close(); renders += 1
    }
}
private final class OverlayChecksRunner: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await PomodoroOverlayChecks.run() }
            catch { preconditionFailure("Pomodoro overlay checks failed: \(error)") }
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
        }
    }
}
