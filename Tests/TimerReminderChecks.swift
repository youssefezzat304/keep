import AVFoundation
import Foundation

@main enum TimerReminderChecks {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    static func main() async throws {
        let suite = "keep.timer-reminders.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        let preferences = AppPreferences(persistence: persistence)
        expect(preferences.showPomodoroTimer && preferences.showPomodoroProgress && preferences.showFlowTimer && preferences.timerSoundsEnabled,
            "Existing timer presentation remains visible and completion sounds default on")
        expect(preferences.flowReminderMinutes == nil, "Flow reminders are opt-in")
        preferences.showPomodoroTimer = false
        preferences.showPomodoroProgress = false
        preferences.showFlowTimer = false
        preferences.timerSoundsEnabled = false
        expect(preferences.setFlowReminder(minutes: 45), "Save a custom reminder")
        let restored = AppPreferences(persistence: persistence)
        expect(!restored.showPomodoroTimer && !restored.showPomodoroProgress && !restored.showFlowTimer && !restored.timerSoundsEnabled
            && restored.flowReminderMinutes == 45, "Timer settings reload from existing preferences storage")
        for invalid in [-1, 0, 1441, Int.max] {
            expect(!restored.setFlowReminder(minutes: invalid) && restored.flowReminderMinutes == 45,
                "Invalid reminder intervals preserve the saved setting")
        }
        for valid in [1, 15, 30, 60, 90, 1440] { expect(restored.setFlowReminder(minutes: valid), "Accept valid whole minutes") }
        let portable = try JSONDecoder().decode(PortableSettings.self, from: JSONEncoder().encode(PortableSettings(restored.snapshot)))
        let imported = portable.applying(to: SettingsArchive())
        expect(imported.showPomodoroTimer == false && imported.showFlowTimer == false && imported.showPomodoroProgress == false
            && imported.timerSoundsEnabled == false && imported.flowReminderMinutes == 1440,
            "Backups retain all new timer preferences")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.snapshot)) as? [String: Any] ?? [:]
        for field in ["showPomodoroTimer", "showPomodoroProgress", "showFlowTimer", "timerSoundsEnabled", "flowReminderMinutes"] {
            legacy.removeValue(forKey: field)
        }
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let migrated = AppPreferences(persistence: persistence)
        expect(migrated.canEdit && migrated.showPomodoroTimer && migrated.showFlowTimer && migrated.showPomodoroProgress
            && migrated.timerSoundsEnabled && migrated.flowReminderMinutes == nil,
            "Older preferences load with compatible defaults")
        var oldPortable = try JSONSerialization.jsonObject(with: JSONEncoder().encode(portable)) as? [String: Any] ?? [:]
        for field in ["showPomodoroTimer", "showPomodoroProgress", "showFlowTimer", "timerSoundsEnabled", "flowReminderMinutes"] { oldPortable.removeValue(forKey: field) }
        let migratedBackup = try JSONDecoder().decode(PortableSettings.self, from: JSONSerialization.data(withJSONObject: oldPortable))
        expect(migratedBackup.applying(to: SettingsArchive()).isValid, "Older portable backups remain valid")
        legacy["flowReminderMinutes"] = 0
        let corrupt = try JSONSerialization.data(withJSONObject: legacy)
        defaults.set(corrupt, forKey: persistence.key)
        let protected = AppPreferences(persistence: persistence)
        expect(!protected.canEdit && !protected.setFlowReminder(minutes: 60), "Corrupt preferences block edits")
        protected.showFlowTimer = false
        expect(defaults.data(forKey: persistence.key) == corrupt, "Validation failures preserve stored bytes")

        let clock = ContinuousClock.now
        let date = Date.now
        func at(_ seconds: Double) -> ContinuousClock.Instant { clock.advanced(by: .seconds(seconds)) }
        func day(_ seconds: Double) -> Date { date.addingTimeInterval(seconds) }
        let options = AppPreferences()
        _ = options.setFlowReminder(minutes: 1)
        let workspace = WorkspaceModel(focusDuration: 60, breakDuration: 30, date: date, timerPreferences: options)
        var sounds: [TimerSound] = []
        workspace.onTimerReminder = { sounds.append($0) }
        func tick(_ seconds: Double) { workspace.synchronize(at: at(seconds), date: day(seconds)) }
        workspace.startBothTimers(at: at(0), date: day(0))
        tick(59)
        expect(sounds.isEmpty, "Neither event fires before its elapsed boundary")
        tick(60)
        expect(sounds == [.focusComplete, .flowReminder], "Independent overlapping timers emit both events")
        tick(60)
        expect(sounds.count == 2, "Repeated refreshes cannot duplicate either event")
        expect(workspace.ledger.sessions.reduce(0) { $0 + $1.seconds } == 60,
            "Reminder events preserve Flow priority without double counting")
        workspace.startBreak(at: at(60), date: day(60))
        tick(90)
        expect(sounds.last == .breakComplete && sounds.count == 3, "Break completion uses its own sound once")
        tick(91)
        expect(sounds.count == 3 && workspace.ledger.completedPomodoros.count == 1, "Break alerts never count as completed focus")
        tick(120)
        expect(sounds.last == .flowReminder && sounds.count == 4, "Flow reminders recur at the chosen cadence")
        workspace.stop(.flow, at: at(130), date: day(130))
        tick(300)
        expect(sounds.count == 4, "A paused Flow timer never emits reminders")
        workspace.play(.flow, at: at(400), date: day(400))
        tick(449)
        expect(sounds.count == 4, "Pause duration does not count toward the next reminder")
        tick(450)
        expect(sounds.count == 5, "Resume preserves the remaining running time")
        workspace.reset(.flow, at: at(460), date: day(460))
        workspace.play(.flow, at: at(461), date: day(461))
        tick(520)
        expect(sounds.count == 5, "Reset starts a fresh reminder countdown")
        tick(521)
        expect(sounds.count == 6, "Reset session gets its own reminders")
        _ = options.setFlowReminder(minutes: 2)
        tick(522)
        tick(641)
        expect(sounds.count == 6, "Changing the interval starts from current elapsed time without catching up")
        tick(642)
        expect(sounds.count == 7, "The new interval takes effect after its full running duration")
        tick(1500)
        expect(sounds.count == 8, "A long delay or sleep produces one reminder, not a burst")
        tick(1500)
        expect(sounds.count == 8, "A late event is delivered at most once")
        options.timerSoundsEnabled = false
        tick(1602)
        let mutedCount = sounds.count
        options.timerSoundsEnabled = true
        tick(1603)
        expect(sounds.count == mutedCount, "Unmuting does not replay reminders consumed while muted")
        options.showPomodoroTimer = false
        options.showFlowTimer = false
        options.showPomodoroProgress = false
        tick(1722)
        expect(sounds.count == mutedCount + 1 && workspace.flow.phase(at: at(1722)) == .running,
            "Hiding visual timers never changes their running state or reminders")
        _ = options.setFlowReminder(minutes: nil)
        tick(1723)
        tick(5000)
        expect(sounds.count == mutedCount + 1, "Turning reminders off cancels future nudges")
        workspace.installBackup(TimesheetLedger())
        tick(6000)
        expect(sounds.count == mutedCount + 1 && workspace.flow.phase(at: at(6000)) == .idle,
            "Restore resets runtime timers without replaying reminders")

        let paused = WorkspaceModel(focusDuration: 10, breakDuration: 5, timerPreferences: options)
        var completions: [TimerSound] = []
        paused.onTimerReminder = { completions.append($0) }
        paused.play(.pomodoro, at: at(0), date: day(0))
        paused.stop(.pomodoro, at: at(4), date: day(4))
        paused.synchronize(at: at(50), date: day(50))
        expect(completions.isEmpty, "Paused Pomodoro cannot complete or sound")
        paused.play(.pomodoro, at: at(50), date: day(50))
        paused.synchronize(at: at(56), date: day(56))
        expect(completions == [.focusComplete], "Resumed focus completes once at its running-time boundary")
        paused.startBreak(at: at(56), date: day(56))
        paused.synchronize(at: at(1000), date: day(1000))
        expect(completions == [.focusComplete, .breakComplete], "Delayed break completion sounds once")
        paused.reset(.pomodoro, at: at(1001), date: day(1001))
        expect(completions.count == 2, "Reset does not replay the previous completion")
        options.timerSoundsEnabled = false
        paused.play(.pomodoro, at: at(1002), date: day(1002))
        paused.synchronize(at: at(1012), date: day(1012))
        options.timerSoundsEnabled = true
        paused.synchronize(at: at(1013), date: day(1013))
        expect(completions.count == 2, "Muted completion remains settled after unmuting")
        paused.shutdown(at: at(1013), date: day(1013))
        workspace.shutdown(at: at(6001), date: day(6001))

        for sound in TimerSound.allCases {
            guard let url = TimerSoundPlayer.resourceURL(for: sound) else { throw CocoaError(.fileNoSuchFile) }
            let audio = try AVAudioPlayer(data: Data(contentsOf: url))
            expect(audio.duration > 1 && audio.duration < 3 && audio.format.sampleRate == 48000
                && audio.format.channelCount == 2 && audio.prepareToPlay(), "Bundled original cue decodes natively")
        }
        // Real native playback, including cancellation while an asset is loading.
        let playback = TimerSoundPlayer()
        playback.play(.focusComplete)
        playback.play(.breakComplete)
        expect(playback.isPlaying, "A queued pair owns one playback job")
        try await Task.sleep(for: .seconds(4.6))
        expect(!playback.isPlaying && playback.errorMessage == nil, "Concurrent events finish without overlapping or audio errors")
        playback.play(.flowReminder)
        playback.stop()
        playback.play(.flowReminder)
        try await Task.sleep(for: .milliseconds(100))
        expect(playback.isPlaying, "A cancelled load cannot clear a newer playback job")
        try await Task.sleep(for: .seconds(1.9))
        expect(!playback.isPlaying && playback.errorMessage == nil, "Flow playback completes after cancellation and restart")
        playback.stop()
        print("Passed \(checks) timer reminder, preference, backup and native audio checks")
    }
}
