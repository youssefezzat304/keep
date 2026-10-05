import Foundation

/// Deterministic recording/editing/persistence checks; no waits or live app data.
@main
enum WorkspaceChecks {
    static var checks = 0

    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3 {
            try persistenceProbe(mode: CommandLine.arguments[1], suite: CommandLine.arguments[2])
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Europe/Berlin") else { preconditionFailure("Missing test timezone") }
        calendar.timeZone = zone
        let day = date(2026, 10, 5, 12, 0, calendar: calendar)
        let origin = ContinuousClock.now
        let keep = FocusProject.defaults[0]
        let german = FocusProject.defaults[1]
        let dayID = TimesheetWeek.dayID(for: day, calendar: calendar)
        func instant(_ seconds: Double) -> ContinuousClock.Instant { origin.advanced(by: .seconds(seconds)) }
        func wall(_ seconds: Double) -> Date { day.addingTimeInterval(seconds) }
        func model(_ duration: Double = 1500) -> WorkspaceModel {
            WorkspaceModel(calendar: calendar, focusDuration: duration, breakDuration: 5, date: day)
        }
        func seconds(_ workspace: WorkspaceModel, _ project: FocusProject = keep) -> Double {
            workspace.ledger.seconds(projectID: project.id, dayID: dayID)
        }

        expect(FocusProject.Accent.projectColors.count == 30, "Exactly 30 selectable project colors")
        expect(Set(FocusProject.Accent.projectColors).count == 30, "Color choices are distinct")
        let catalog = model()
        let created = try catalog.createProject(name: "  Autumn notes\n", accent: .plum, at: instant(0), date: wall(0))
        expect(created.name == "Autumn notes" && created.accent == .plum, "Creation trims the name and keeps the chosen color")
        expect(catalog.projects.contains(created), "Created project joins the shared catalog")
        expect(catalog.ledger.entries.isEmpty, "Creation alone does not fabricate time or a weekly row")
        expect(catalog.selectedProject == keep, "Catalog registration does not change the active project")
        for (name, color) in [(" \n ", FocusProject.Accent.sage), (String(repeating: "a", count: 81), .sage), ("autumn NOTES", .sage), ("No project", .sage), ("Another", .neutral)] {
            do {
                _ = try catalog.createProject(name: name, accent: color, at: instant(0), date: wall(0))
                preconditionFailure("Invalid project should not be created")
            } catch is ProjectCreationError {
                expect(catalog.ledger.customProjects.count == 1, "Invalid creation leaves the catalog unchanged")
            }
        }
        catalog.play(.flow, at: instant(0), date: wall(0))
        let next = try catalog.createProject(name: "Sketchbook", accent: .seafoam, at: instant(10), date: wall(10))
        catalog.selectProject(next, at: instant(10), date: wall(10))
        catalog.stop(.flow, at: instant(20), date: wall(20))
        near(seconds(catalog), 10, "Creating and selecting while running settles the old project")
        near(seconds(catalog, next), 10, "New project records only subsequent time")
        catalog.edit(seconds: 90, project: next, dayID: dayID, at: instant(20), date: wall(20))
        near(seconds(catalog, next), 90, "Created project supports manual time edits")
        let week = TimesheetWeek(containing: day, calendar: calendar)
        let previousDate = day.addingTimeInterval(-7 * 86400)
        let previousDay = TimesheetWeek.dayID(for: previousDate, calendar: calendar)
        catalog.edit(seconds: 42, project: next, dayID: previousDay, at: instant(20), date: wall(20))
        let tuesday = week.days[1].id
        catalog.edit(seconds: 30, project: next, dayID: tuesday, at: instant(20), date: wall(20))
        catalog.edit(seconds: 15, project: created, dayID: dayID, at: instant(20), date: wall(20))
        catalog.removeTimesheetProject(next, dayIDs: week.dayIDs, at: instant(20), date: wall(20))
        near(seconds(catalog, next), 0, "Removing a weekly row deletes its time")
        expect(!catalog.ledger.projects(dayIDs: week.dayIDs).contains(next), "Removed row disappears instead of keeping empty cells")
        near(catalog.ledger.seconds(projectID: next.id, dayID: tuesday), 0, "Removal deletes all days in the selected week")
        near(catalog.ledger.seconds(projectID: next.id, dayID: previousDay), 42, "Removal preserves other weeks")
        near(seconds(catalog, created), 15, "Removal preserves other projects")
        expect(catalog.projects.contains(next) && catalog.selectedProject == next, "Removal keeps catalog and selected project")
        catalog.undoTimesheetRemoval(at: instant(20), date: wall(20))
        near(seconds(catalog, next), 90, "Undo restores removed time")
        near(catalog.ledger.seconds(projectID: next.id, dayID: tuesday), 30, "Undo restores every removed day")
        expect(catalog.lastTimesheetRemoval == nil, "Undo is consumed once")
        catalog.undoTimesheetRemoval(at: instant(20), date: wall(20))
        near(seconds(catalog, next), 90, "Repeated Undo cannot duplicate time")

        let deletingLive = model()
        deletingLive.play(.flow, at: instant(0), date: wall(0))
        deletingLive.removeTimesheetProject(keep, dayIDs: week.dayIDs, at: instant(10), date: wall(10))
        expect(deletingLive.ledger.entries.isEmpty && deletingLive.lastTimesheetRemoval?.entries.first?.seconds == 10, "Live removal settles then deletes all time up to the click")
        expect(deletingLive.flow.phase(at: instant(10)) == .running, "Removing time does not stop its timer")
        deletingLive.synchronize(at: instant(15), date: wall(15))
        near(seconds(deletingLive), 5, "Future time recreates the row without resurrecting deleted time")
        deletingLive.undoTimesheetRemoval(at: instant(20), date: wall(20))
        near(seconds(deletingLive), 20, "Undo merges old time with time recorded after removal")
        deletingLive.removeTimesheetProject(keep, dayIDs: [previousDay], at: instant(20), date: wall(20))
        near(seconds(deletingLive), 20, "Removing a nonexistent historical row leaves current time intact")

        let deletingEmpty = model()
        deletingEmpty.addProject(.unassigned, on: day, at: instant(0), now: wall(0))
        deletingEmpty.removeTimesheetProject(.unassigned, dayIDs: week.dayIDs, at: instant(0), date: wall(0))
        expect(deletingEmpty.ledger.entries.isEmpty, "Zero-time and unassigned rows can be removed")
        deletingEmpty.undoTimesheetRemoval(at: instant(0), date: wall(0))
        expect(deletingEmpty.ledger.projects(dayIDs: week.dayIDs) == [.unassigned], "Undo restores zero-time rows")

        let deletingFocus = model(10)
        deletingFocus.play(.pomodoro, at: instant(0), date: wall(0))
        deletingFocus.removeTimesheetProject(keep, dayIDs: week.dayIDs, at: instant(5), date: wall(5))
        deletingFocus.synchronize(at: instant(12), date: wall(12))
        near(seconds(deletingFocus), 5, "Deleting running focus keeps only subsequent focus time, capped at completion")
        expect(deletingFocus.pomodoro.completedFocusIntervals == 1, "Removing time does not reset Pomodoro cycle progress")
        deletingFocus.startBreak(at: instant(12), date: wall(12))
        deletingFocus.undoTimesheetRemoval(at: instant(15), date: wall(15))
        near(seconds(deletingFocus), 10, "Undo during a break restores focus time without counting the break")
        let legacy = try JSONDecoder().decode(TimesheetLedger.self, from: Data("{\"entries\":[]}".utf8))
        expect(legacy.customProjects.isEmpty, "Existing v1 data loads without a catalog field")
        for color in FocusProject.Accent.projectColors {
            let data = try JSONEncoder().encode(color)
            expect(try JSONDecoder().decode(FocusProject.Accent.self, from: data) == color, "Color survives encoding: \(color)")
        }

        let pomodoro = model(10)
        pomodoro.play(.pomodoro, at: instant(0), date: wall(0))
        expect(pomodoro.ledger.projects(dayIDs: [dayID]).count == 1, "Start adds a project row immediately")
        near(seconds(pomodoro), 0, "Start does not invent time")
        pomodoro.synchronize(at: instant(4), date: wall(4))
        near(seconds(pomodoro), 4, "Live focus count")
        pomodoro.synchronize(at: instant(4), date: wall(4))
        near(seconds(pomodoro), 4, "Duplicate refresh does not double count")
        pomodoro.stop(.pomodoro, at: instant(6), date: wall(6))
        pomodoro.synchronize(at: instant(30), date: wall(30))
        near(seconds(pomodoro), 6, "Paused time excluded")
        pomodoro.play(.pomodoro, at: instant(40), date: wall(40))
        pomodoro.synchronize(at: instant(46), date: wall(46))
        near(seconds(pomodoro), 10, "Delayed completion caps focus time exactly")
        expect(pomodoro.pomodoro.phase(at: instant(46)) == .completed, "Focus completes without automatically starting a break")
        pomodoro.startBreak(at: instant(50), date: wall(50))
        expect(pomodoro.pomodoro.interval == .rest, "Manual break starts rest interval")
        expect(pomodoro.pomodoro.display(at: instant(50)) == "00:05", "Break duration")
        pomodoro.synchronize(at: instant(53), date: wall(53))
        near(seconds(pomodoro), 10, "Break is not recorded")
        expect(pomodoro.flow.phase(at: instant(53)) == .idle, "Starting a break does not start Flow")
        pomodoro.play(.flow, at: instant(53), date: wall(53))
        pomodoro.synchronize(at: instant(57), date: wall(57))
        near(seconds(pomodoro), 14, "Flow records even during Pomodoro rest")
        expect(pomodoro.pomodoro.phase(at: instant(57)) == .completed, "Manual break completes and waits")
        pomodoro.stop(.flow, at: instant(57), date: wall(57))
        pomodoro.synchronize(at: instant(60), date: wall(60))
        near(seconds(pomodoro), 14, "Completed break does not record")
        pomodoro.play(.pomodoro, at: instant(65), date: wall(65))
        expect(pomodoro.pomodoro.interval == .focus, "Play after break starts focus again")
        pomodoro.reset(.pomodoro, at: instant(68), date: wall(68))
        near(seconds(pomodoro), 17, "Reset settles time without deleting recorded history")
        pomodoro.synchronize(at: instant(100), date: wall(100))
        near(seconds(pomodoro), 17, "Reset stops counting")

        let settings = PomodoroSettings(focusMinutes: 1, shortBreakMinutes: 2, longBreakMinutes: 3, iterationsBeforeLongBreak: 2)
        let configured = model(10)
        configured.play(.pomodoro, at: instant(0), date: wall(0))
        expect(configured.updatePomodoroSettings(settings, at: instant(5), date: wall(5)), "Apply valid settings while running")
        near(seconds(configured), 5, "Settings change settles recorded time")
        expect(configured.pomodoro.focusDuration == 10, "Settings do not change active focus duration")
        configured.startBreak(at: instant(15), date: wall(15))
        near(seconds(configured), 10, "Delayed focus completion caps at original duration after settings change")
        expect(configured.pomodoro.breakDuration == 120 && !configured.pomodoro.isLongBreak, "First focus offers configured short break")
        configured.play(.pomodoro, at: instant(135), date: wall(135))
        expect(configured.pomodoro.focusDuration == 60, "Next focus uses new duration")
        configured.startBreak(at: instant(195), date: wall(195))
        expect(configured.pomodoro.isLongBreak && configured.pomodoro.breakDuration == 180, "Configured iteration threshold offers long break")
        configured.synchronize(at: instant(205), date: wall(205))
        near(seconds(configured), 70, "Neither short nor long break contributes Pomodoro time")
        configured.play(.flow, at: instant(205), date: wall(205))
        configured.updatePomodoroSettings(PomodoroSettings(focusMinutes: 3), at: instant(210), date: wall(210))
        expect(configured.flow.phase(at: instant(210)) == .running, "Settings leave Flow running")
        near(seconds(configured), 75, "Flow priority continues during long break and settings change")
        let retained = configured.pomodoroSettings
        expect(!configured.updatePomodoroSettings(PomodoroSettings(focusMinutes: 0), at: instant(210), date: wall(210)), "Invalid focus settings rejected")
        expect(!configured.updatePomodoroSettings(PomodoroSettings(iterationsBeforeLongBreak: 13), at: instant(210), date: wall(210)), "Invalid iteration settings rejected")
        expect(!configured.updatePomodoroSettings(PomodoroSettings(shortBreakMinutes: 61), at: instant(210), date: wall(210)), "Invalid short break settings rejected")
        expect(!configured.updatePomodoroSettings(PomodoroSettings(longBreakMinutes: 0), at: instant(210), date: wall(210)), "Invalid long break settings rejected")
        expect(configured.pomodoroSettings == retained, "Invalid settings preserve saved configuration")

        let pausedBreak = model(2)
        pausedBreak.startBreak(at: instant(0), date: wall(0))
        expect(pausedBreak.pomodoro.interval == .focus && pausedBreak.pomodoro.phase(at: instant(0)) == .idle, "Break unavailable before completed focus")
        pausedBreak.play(.pomodoro, at: instant(0), date: wall(0))
        pausedBreak.startBreak(at: instant(2), date: wall(2))
        pausedBreak.stop(.pomodoro, at: instant(4), date: wall(4))
        pausedBreak.synchronize(at: instant(20), date: wall(20))
        expect(pausedBreak.pomodoro.display(at: instant(20)) == "00:03", "Paused break stays frozen")
        pausedBreak.play(.pomodoro, at: instant(20), date: wall(20))
        expect(pausedBreak.pomodoro.interval == .rest, "Continue resumes rest rather than starting focus")
        pausedBreak.synchronize(at: instant(23), date: wall(23))
        near(seconds(pausedBreak), 2, "Paused and resumed rest never contributes time")
        pausedBreak.reset(.pomodoro, at: instant(24), date: wall(24))
        expect(pausedBreak.pomodoro.interval == .focus && pausedBreak.pomodoro.phase(at: instant(24)) == .idle, "Reset during rest returns to fresh focus")

        let overlap = model(100)
        overlap.play(.pomodoro, at: instant(0), date: wall(0))
        overlap.play(.flow, at: instant(10), date: wall(10))
        overlap.synchronize(at: instant(30), date: wall(30))
        near(seconds(overlap), 30, "Overlap counts each second once")
        near(overlap.pomodoro.elapsed(at: instant(30)), 30, "Pomodoro keeps running independently")
        near(overlap.flow.elapsed(at: instant(30)), 20, "Flow keeps its own elapsed time")
        overlap.stop(.flow, at: instant(30), date: wall(30))
        overlap.synchronize(at: instant(40), date: wall(40))
        near(seconds(overlap), 40, "Stopping Flow falls back to running focus")
        overlap.stop(.pomodoro, at: instant(40), date: wall(40))
        overlap.play(.flow, at: instant(60), date: wall(60))
        overlap.reset(.pomodoro, at: instant(70), date: wall(70))
        overlap.synchronize(at: instant(80), date: wall(80))
        near(seconds(overlap), 60, "Resetting Pomodoro does not interrupt Flow recording")
        overlap.play(.pomodoro, at: instant(80), date: wall(80))
        overlap.reset(.flow, at: instant(90), date: wall(90))
        overlap.synchronize(at: instant(100), date: wall(100))
        near(seconds(overlap), 80, "Resetting Flow falls back to focus without losing time")

        let beyondFocus = model(10)
        beyondFocus.play(.pomodoro, at: instant(0), date: wall(0))
        beyondFocus.play(.flow, at: instant(0), date: wall(0))
        beyondFocus.synchronize(at: instant(31), date: wall(31))
        near(seconds(beyondFocus), 31, "Flow overrides focus cap across a delayed refresh")
        beyondFocus.stop(.flow, at: instant(35), date: wall(35))
        beyondFocus.synchronize(at: instant(50), date: wall(50))
        near(seconds(beyondFocus), 35, "No phantom focus after Flow stops on completed Pomodoro")

        let switching = model()
        switching.play(.flow, at: instant(0), date: wall(0))
        switching.selectProject(german, at: instant(10), date: wall(10))
        switching.synchronize(at: instant(20), date: wall(20))
        near(seconds(switching), 10, "Project switch settles old project")
        near(seconds(switching, german), 10, "New project receives only later time")
        switching.selectProject(nil, at: instant(25), date: wall(25))
        switching.stop(.flow, at: instant(35), date: wall(35))
        near(seconds(switching, german), 15, "Switching to unassigned settles selected project")
        near(seconds(switching, .unassigned), 10, "Unassigned time has its own row")
        switching.selectProject(keep, at: instant(40), date: wall(40))
        switching.synchronize(at: instant(50), date: wall(50))
        near(seconds(switching), 10, "Changing project while stopped does not count")

        let editing = model()
        editing.play(.flow, at: instant(0), date: wall(0))
        editing.edit(seconds: 3600, project: keep, dayID: dayID, at: instant(20), date: wall(20))
        near(seconds(editing), 3600, "Edit replaces the settled total")
        editing.synchronize(at: instant(25), date: wall(25))
        near(seconds(editing), 3605, "Running timer adds only future time after edit")
        near(editing.flow.elapsed(at: instant(25)), 25, "Edit does not reset the timer")
        editing.edit(seconds: 0, project: keep, dayID: dayID, at: instant(30), date: wall(30))
        editing.synchronize(at: instant(35), date: wall(35))
        near(seconds(editing), 5, "Clearing an active cell does not re-add old timer time")
        editing.edit(seconds: -1, project: keep, dayID: dayID, at: instant(35), date: wall(35))
        near(seconds(editing), 5, "Negative edit rejected")
        editing.edit(seconds: .infinity, project: keep, dayID: dayID, at: instant(35), date: wall(35))
        near(seconds(editing), 5, "Infinite edit rejected")

        let fraction = model()
        fraction.play(.flow, at: instant(0), date: wall(0))
        fraction.synchronize(at: instant(0.25), date: wall(0.25))
        fraction.synchronize(at: instant(0.75), date: wall(0.75))
        fraction.stop(.flow, at: instant(1.55), date: wall(1.55))
        near(seconds(fraction), 1.55, "Subsecond intervals are retained without per-tick rounding")
        expect(TimesheetDuration.clock(seconds(fraction)) == "0:00:01", "Display floors only at presentation")

        let sunday = date(2026, 10, 4, 23, 59, calendar: calendar).addingTimeInterval(30)
        let midnight = model()
        midnight.play(.flow, at: instant(0), date: sunday)
        midnight.synchronize(at: instant(90), date: sunday.addingTimeInterval(90))
        near(midnight.ledger.seconds(projectID: keep.id, dayID: "2026-10-04"), 30, "Old day gets time before midnight")
        near(midnight.ledger.seconds(projectID: keep.id, dayID: "2026-10-05"), 60, "New day gets time after midnight")
        let currentWeek = TimesheetWeek(containing: sunday.addingTimeInterval(90), calendar: calendar)
        expect(currentWeek.days.count == 7 && currentWeek.days[0].id == "2026-10-05" && currentWeek.days[6].id == "2026-10-11", "Monday to Sunday week boundaries")
        expect(currentWeek.number == "W41", "ISO week number")
        near(midnight.ledger.total(dayIDs: currentWeek.dayIDs), 60, "Week rollover excludes last week's seconds")

        var dstLedger = TimesheetLedger()
        dstLedger.record(project: keep, from: date(2026, 10, 25, 0, 0, calendar: calendar), seconds: 26 * 3600, calendar: calendar)
        near(dstLedger.seconds(projectID: keep.id, dayID: "2026-10-25"), 25 * 3600, "DST fall day has 25 hours")
        near(dstLedger.seconds(projectID: keep.id, dayID: "2026-10-26"), 3600, "DST fall remainder goes to next day")
        dstLedger.record(project: keep, from: date(2026, 3, 29, 0, 0, calendar: calendar), seconds: 24 * 3600, calendar: calendar)
        near(dstLedger.seconds(projectID: keep.id, dayID: "2026-03-29"), 23 * 3600, "DST spring day has 23 hours")
        near(dstLedger.seconds(projectID: keep.id, dayID: "2026-03-30"), 3600, "DST spring remainder goes to next day")

        let clockJump = model()
        clockJump.play(.flow, at: instant(0), date: wall(0))
        clockJump.synchronize(at: instant(60), date: wall(3600))
        clockJump.synchronize(at: instant(120), date: wall(-3600))
        near(seconds(clockJump), 120, "Wall-clock jumps do not change recorded duration")

        expect(TimesheetDuration.parse(" 2:15 ") == 8100, "Parse hours and minutes")
        expect(TimesheetDuration.parse("0:00:15") == 15, "Parse exact seconds")
        expect(TimesheetDuration.parse(" \n") == 0, "Blank clears entry")
        for invalid in ["-1:00", "1:60", "0:12:60", "1", "1.5:00", ":15", "1:", "1:00:00:00", "10000:00", "abc", "1:+2", "nan:00"] {
            expect(TimesheetDuration.parse(invalid) == nil, "Reject malformed duration \(invalid)")
        }
        expect(TimesheetDuration.clock(3661) == "1:01:01", "Clock formats hours without losing seconds")
        expect(TimesheetDuration.total(15) == "15s", "Short sessions have visible totals")
        expect(TimesheetDuration.total(8100) == "2h 15m", "Hour totals")

        let suite = "keep.workspace-checks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Cannot create isolated preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let saved = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        saved.play(.flow, at: instant(0), date: wall(0))
        saved.edit(seconds: 7200, project: keep, dayID: dayID, at: instant(15), date: wall(15))
        saved.shutdown(at: instant(20), date: wall(20))
        let reloaded = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        near(seconds(reloaded), 7205, "Recorded time and manual edits survive model reload")
        expect(reloaded.flow.phase(at: instant(30)) == .idle && reloaded.pomodoro.phase(at: instant(30)) == .idle, "Relaunch does not count app-offline time")
        reloaded.play(.flow, at: instant(30), date: wall(30))
        reloaded.stop(.flow, at: instant(35), date: wall(35))
        near(seconds(reloaded), 7210, "New recording adds to saved totals")
        near(try persistence.load().seconds(projectID: keep.id, dayID: dayID), 7210, "Stop saves immediately")

        let savedProject = try reloaded.createProject(name: "Saved before any time", accent: .walnut, at: instant(35), date: wall(35))
        let catalogReload = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        expect(catalogReload.projects.contains(savedProject), "Name, identity, and color persist before the first session")
        expect(catalogReload.ledger.entries.allSatisfy { $0.project.id != savedProject.id }, "Saved catalog does not invent entries")
        near(seconds(catalogReload), 7210, "Adding a saved catalog preserves previous time")
        reloaded.updatePomodoroSettings(settings, at: instant(35), date: wall(35))
        let settingsReload = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        expect(settingsReload.pomodoroSettings == settings && settingsReload.pomodoro.focusDuration == 60, "Settings survive reload and configure the idle timer")
        expect(settingsReload.pomodoro.completedFocusIntervals == 0, "Runtime cycle progress is not restored")
        expect(settingsReload.projects.contains(savedProject), "Saving settings preserves custom projects")
        near(seconds(settingsReload), 7210, "Saving settings preserves recorded time")
        settingsReload.removeTimesheetProject(keep, dayIDs: week.dayIDs, at: instant(35), date: wall(35))
        let removedReload = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        expect(!removedReload.ledger.projects(dayIDs: week.dayIDs).contains(keep), "Row deletion persists across reload")
        expect(removedReload.projects.contains(savedProject) && removedReload.pomodoroSettings == settings, "Deletion preserves saved catalog and settings")
        settingsReload.undoTimesheetRemoval(at: instant(35), date: wall(35))
        near(try persistence.load().seconds(projectID: keep.id, dayID: dayID), 7210, "Undo persists restored time immediately")

        let oldRecords = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reloaded.ledger)) as? [String: Any]
        let oldData = try JSONSerialization.data(withJSONObject: ["entries": oldRecords?["entries"] ?? []])
        defaults.set(oldData, forKey: persistence.key)
        let legacyReload = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        expect(legacyReload.canTrack && legacyReload.ledger.customProjects.isEmpty, "Old saved records migrate without a load failure")
        expect(legacyReload.pomodoroSettings == .defaults, "Old records use default settings")
        near(seconds(legacyReload), 7210, "Old saved records retain exact totals")

        var invalidSettingsLedger = reloaded.ledger
        invalidSettingsLedger.setPomodoroSettings(PomodoroSettings(focusMinutes: 0))
        try persistence.save(invalidSettingsLedger)
        let invalidSettingsLoad = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        expect(invalidSettingsLoad.loadFailed && !invalidSettingsLoad.canTrack, "Invalid saved settings are protected as corrupt data")

        let corruptData = Data("invalid saved JSON".utf8)
        defaults.set(corruptData, forKey: persistence.key)
        let failed = WorkspaceModel(persistence: persistence, calendar: calendar, date: day)
        expect(failed.loadFailed && !failed.canTrack && failed.persistenceError != nil, "Corrupt data surfaces an actionable error")
        failed.play(.flow, at: instant(0), date: wall(0))
        failed.edit(seconds: 50, project: keep, dayID: dayID, at: instant(10), date: wall(10))
        failed.removeTimesheetProject(keep, dayIDs: week.dayIDs, at: instant(10), date: wall(10))
        expect(failed.ledger.entries.isEmpty && failed.flow.phase(at: instant(10)) == .idle, "Failed load blocks edits and recording")
        expect(!failed.updatePomodoroSettings(settings), "Failed load blocks settings writes")
        do {
            _ = try failed.createProject(name: "Blocked", accent: .sage)
            preconditionFailure("Creation must not overwrite unreadable data")
        } catch is ProjectCreationError {
            expect(failed.ledger.customProjects.isEmpty, "Failed load also blocks project creation")
        }
        expect(defaults.data(forKey: persistence.key) == corruptData, "Failed load never overwrites stored records")
        try persistence.save(reloaded.ledger)
        failed.retryPersistence()
        expect(failed.canTrack && failed.persistenceError == nil, "Retry can recover a readable ledger")
        near(seconds(failed), 7210, "Recovered ledger keeps saved totals")

        let processSuite = "keep.persistence-probe.\(UUID().uuidString)"
        guard let probeDefaults = UserDefaults(suiteName: processSuite) else { preconditionFailure("Cannot create process preferences") }
        defer { probeDefaults.removePersistentDomain(forName: processSuite) }
        for mode in ["--write-probe", "--read-probe"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [mode, processSuite]
            try process.run()
            process.waitUntilExit()
            expect(process.terminationStatus == 0, "Persistence survives a separate write/read process: \(mode)")
        }

        var manual = TimesheetLedger()
        manual.setSeconds(12, project: keep, dayID: dayID)
        manual.setSeconds(23, project: german, dayID: dayID)
        near(manual.total(dayIDs: [dayID]), 35, "Daily and weekly totals derive from cell values")
        near(manual.total(dayIDs: [dayID], projectID: keep.id), 12, "Project totals derive from cell values")
        print("Passed \(checks) deterministic workspace checks: recording, Flow priority, manual breaks, editing, midnight/DST, duration validation, and persistence.")
    }

    private static func persistenceProbe(mode: String, suite: String) throws {
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Cannot open probe preferences") }
        let persistence = TimesheetPersistence(defaults: defaults)
        if mode == "--write-probe" {
            var ledger = TimesheetLedger()
            ledger.setSeconds(2715, project: FocusProject.defaults[1], dayID: "2026-10-05")
            ledger.registerProject(FocusProject(id: "probe-project", name: "Across launches", accent: .lavender, category: "Personal project"))
            ledger.setPomodoroSettings(PomodoroSettings(focusMinutes: 45, shortBreakMinutes: 7, longBreakMinutes: 20, iterationsBeforeLongBreak: 3))
            try persistence.save(ledger)
        } else if mode == "--read-probe" {
            let ledger = try persistence.load()
            near(ledger.seconds(projectID: "german", dayID: "2026-10-05"), 2715, "Cross-process saved value")
            expect(ledger.customProjects.first?.id == "probe-project" && ledger.customProjects.first?.accent == .lavender, "Cross-process project catalog persists without recorded time")
            expect(ledger.pomodoroSettings?.focusMinutes == 45 && ledger.pomodoroSettings?.iterationsBeforeLongBreak == 3, "Cross-process Pomodoro settings persist")
        } else { preconditionFailure("Unknown probe mode") }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) else { preconditionFailure("Invalid fixture date") }
        return value
    }

    private static func expect(_ condition: Bool, _ description: String) {
        checks += 1
        precondition(condition, description)
    }

    private static func near(_ actual: Double, _ expected: Double, _ description: String) {
        expect(abs(actual - expected) < 0.00001, "\(description): expected \(expected), got \(actual)")
    }
}
