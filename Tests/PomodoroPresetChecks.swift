import Foundation

@main enum PomodoroPresetChecks {
    static var count = 0
    static func expect(_ condition: Bool, _ message: String) { count += 1; precondition(condition, message) }
    static func rejects(_ message: String, _ action: () throws -> Void) {
        do { try action(); preconditionFailure(message) } catch { count += 1 }
    }

    static func main() throws {
        let suite = "keep.preset-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let origin = Date(timeIntervalSince1970: 1_791_619_200)
        let instant = ContinuousClock.now
        func tick(_ seconds: Int) -> ContinuousClock.Instant { instant.advanced(by: .seconds(seconds)) }
        func date(_ seconds: Int) -> Date { origin.addingTimeInterval(Double(seconds)) }
        let rhythm = PomodoroSettings(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20, iterationsBeforeLongBreak: 3)
        let workspace = WorkspaceModel(persistence: persistence, date: origin)
        expect(workspace.pomodoroPresets.isEmpty, "New workspaces start without invented presets")
        try workspace.savePomodoroPreset(name: "  Writing  ", settings: rhythm, at: tick(0), date: date(0))
        guard let preset = workspace.pomodoroPresets.first else { preconditionFailure("Preset was not saved") }
        expect(preset.name == "Writing" && preset.settings == rhythm, "Saving trims the name and keeps all four values")
        expect(workspace.pomodoroSettings == .defaults && workspace.pomodoro.focusDuration == 1500, "Save preset does not apply its values")
        let reopened = WorkspaceModel(persistence: persistence, date: origin)
        expect(reopened.pomodoroPresets == [preset], "Presets survive reopening with stable identities")
        expect(reopened.updatePomodoroSettings(preset.settings, at: tick(0), date: date(0)), "Applying uses the existing workspace settings action")
        expect(reopened.pomodoro.focusDuration == 3000 && reopened.pomodoro.shortBreakDuration == 600 && reopened.pomodoro.longBreakDuration == 1200 && reopened.pomodoro.iterationsBeforeLongBreak == 3, "Applying an idle preset updates all timer values")
        expect(try persistence.load().pomodoroSettings == rhythm, "Applied settings persist")

        rejects("Empty names are rejected") { try workspace.savePomodoroPreset(name: " \n ", settings: rhythm) }
        rejects("Long names are rejected") { try workspace.savePomodoroPreset(name: String(repeating: "a", count: 81), settings: rhythm) }
        rejects("Names match without case or accents") { try workspace.savePomodoroPreset(name: "WRÍTÍNG", settings: rhythm) }
        for invalid in [PomodoroSettings(focusMinutes: 0), PomodoroSettings(shortBreakMinutes: 61), PomodoroSettings(longBreakMinutes: 121), PomodoroSettings(iterationsBeforeLongBreak: 13)] {
            rejects("Invalid preset values never enter the archive") { try workspace.savePomodoroPreset(name: "Invalid", settings: invalid) }
        }
        expect(workspace.pomodoroPresets == [preset], "Rejected saves leave the catalog untouched")

        let payload = BackupPayload(workspace: reopened.ledger, tasks: TaskArchive(), habits: HabitArchive(), settings: PortableSettings(SettingsArchive()))
        let envelope = try BackupEnvelope(snapshot: payload, deviceID: UUID(), date: origin, appVersion: "0.1.0")
        let decoded = try BackupEnvelope.decode(JSONEncoder().encode(envelope)).validatedPayload()
        expect(decoded.workspace.pomodoroPresets == [preset], "Validated backups include presets")
        let restored = WorkspaceModel()
        restored.installBackup(decoded.workspace)
        expect(restored.pomodoroPresets == [preset] && restored.pomodoroSettings == rhythm && restored.pomodoro.phase() == .idle, "Restore installs presets without restoring live timers")

        try reopened.removePomodoroPreset(id: preset.id, at: tick(0), date: date(0))
        expect(reopened.pomodoroPresets.isEmpty && reopened.pomodoroSettings == rhythm, "Deleting a preset leaves the applied rhythm intact")
        expect(try persistence.load().pomodoroPresets.isEmpty, "Deletion persists")
        rejects("Stale deletion is reported") { try reopened.removePomodoroPreset(id: preset.id) }

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reopened.ledger)) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "pomodoroPresets")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: persistence.key)
        let migrated = WorkspaceModel(persistence: persistence, date: origin)
        expect(!migrated.loadFailed && migrated.pomodoroPresets.isEmpty && migrated.pomodoroSettings == rhythm, "Old archives load with no presets and keep timer settings")

        var corrupt = TimesheetLedger()
        corrupt.addPomodoroPreset(preset)
        corrupt.addPomodoroPreset(PomodoroPreset(id: UUID(), name: "WRITING", settings: rhythm))
        rejects("Duplicate names in imported archives are rejected") { try TimesheetPersistence.validate(corrupt) }
        var invalidID = TimesheetLedger()
        invalidID.addPomodoroPreset(preset)
        invalidID.addPomodoroPreset(PomodoroPreset(id: preset.id, name: "Other", settings: rhythm))
        rejects("Duplicate preset identities are rejected") { try TimesheetPersistence.validate(invalidID) }
        var invalidValues = TimesheetLedger()
        invalidValues.addPomodoroPreset(PomodoroPreset(id: UUID(), name: "Bad", settings: PomodoroSettings(focusMinutes: 181)))
        rejects("Imported invalid durations are rejected") { try TimesheetPersistence.validate(invalidValues) }
        var invalidName = TimesheetLedger()
        invalidName.addPomodoroPreset(PomodoroPreset(id: UUID(), name: "  ", settings: rhythm))
        rejects("Imported invalid names are rejected") { try TimesheetPersistence.validate(invalidName) }
        try persistence.save(corrupt)
        let savedBytes = defaults.data(forKey: persistence.key)
        let protected = WorkspaceModel(persistence: persistence, date: origin)
        rejects("Invalid archive blocks creation") { try protected.savePomodoroPreset(name: "Protected", settings: rhythm) }
        rejects("Invalid archive blocks deletion") { try protected.removePomodoroPreset(id: preset.id) }
        expect(protected.loadFailed && defaults.data(forKey: persistence.key) == savedBytes, "Corrupt preset archives are preserved for recovery")

        let gate = BackupRestoreGate()
        gate.isLocked = true
        var lockedPersistence = TimesheetPersistence(defaults: defaults, key: "locked")
        lockedPersistence.access = gate
        let locked = WorkspaceModel(persistence: lockedPersistence, date: origin)
        rejects("Restore gate blocks preset mutations") { try locked.savePomodoroPreset(name: "Locked", settings: rhythm) }

        let active = WorkspaceModel(focusDuration: 10, breakDuration: 5, date: origin)
        active.play(.pomodoro, at: tick(0), date: date(0))
        try active.savePomodoroPreset(name: "Study", settings: rhythm, at: tick(2), date: date(2))
        expect(active.pomodoro.seconds(at: tick(2)) == 8 && active.pomodoro.focusDuration == 10, "Saving a preset leaves the active interval unchanged")
        expect(active.updatePomodoroSettings(rhythm, at: tick(3), date: date(3)), "A running interval accepts a future rhythm")
        expect(active.pomodoro.focusDuration == 10 && active.pomodoro.seconds(at: tick(3)) == 7, "Running focus retains original duration and elapsed time")
        active.stop(.pomodoro, at: tick(4), date: date(4))
        let pausedRhythm = PomodoroSettings(focusMinutes: 40, shortBreakMinutes: 8, longBreakMinutes: 16, iterationsBeforeLongBreak: 1)
        expect(active.updatePomodoroSettings(pausedRhythm, at: tick(7), date: date(7)), "Paused interval accepts a future rhythm")
        expect(active.pomodoro.phase(at: tick(7)) == .stopped && active.pomodoro.seconds(at: tick(7)) == 6, "Paused focus retains its duration and pause state")
        active.play(.pomodoro, at: tick(7), date: date(7))
        active.synchronize(at: tick(14), date: date(14))
        expect(active.ledger.completedPomodoros.count == 1 && active.pomodoro.completedFocusIntervals == 1, "Applying presets counts the original completion once")
        active.startBreak(at: tick(14), date: date(14))
        expect(active.pomodoro.isLongBreak && active.pomodoro.breakDuration == 960, "The next break uses the latest preset cycle and duration")
        active.updatePomodoroSettings(rhythm, at: tick(16), date: date(16))
        expect(active.pomodoro.breakDuration == 960 && active.pomodoro.seconds(at: tick(16)) == 958, "Running breaks keep their duration when presets change")

        let both = WorkspaceModel(date: origin)
        both.startBothTimers(at: tick(0), date: date(0))
        try both.savePomodoroPreset(name: "Concurrent", settings: rhythm, at: tick(3), date: date(3))
        both.updatePomodoroSettings(rhythm, at: tick(5), date: date(5))
        both.stopBothTimers(at: tick(8), date: date(8))
        expect(both.ledger.sessions.reduce(0) { $0 + $1.seconds } == 8 && both.ledger.sessions.allSatisfy { $0.source == .flow }, "Preset actions settle concurrent recording without double counting")
        print("Passed \(count) Pomodoro preset checks")
    }
}
