import AppKit
import SwiftUI

@main enum ProjectRateChecks {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
    static func rejects(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Invalid project operation accepted") } catch { checks += 1 }
    }
    static func payload(_ ledger: TimesheetLedger) -> KeepDataPayload {
        .init(backup: .init(workspace: ledger, tasks: .init(), habits: .init(), settings: PortableSettings(.init())), timeZone: "UTC")
    }
    static func main() async throws {
        _ = NSApplication.shared
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12)) ?? .distantPast
        let clock = ContinuousClock.now
        let eur = ProjectHourlyRate(amount: Decimal(string: "80.25") ?? 0, currency: "EUR")
        let usd = ProjectHourlyRate(amount: 100, currency: "USD")
        expect(FocusProject.Accent.projectColors.count == 30 && !FocusProject.Accent.projectColors.contains(.habits), "Thirty public colors exclude the protected Habits accent")
        expect(Set(ProjectHourlyRate.currencies) == Set(Locale.commonISOCurrencyCodes), "Currency choices use Apple's complete common ISO currency list")
        expect(try ProjectHourlyRate.parse("  ", currency: "EUR") == nil, "Empty rates are optional")
        expect(try ProjectHourlyRate.parse("80,25", currency: "EUR", locale: Locale(identifier: "de_DE")) == eur, "Localized decimal entry keeps cents")
        expect(try ProjectHourlyRate.parse("80.25", currency: "EUR", locale: Locale(identifier: "en_US")) == eur, "English decimal entry keeps cents")
        for text in ["12abc", "12.50 garbage", "-1", "NaN", "1e100", "1.2.3", "1000000000001"] {
            rejects { _ = try ProjectHourlyRate.parse(text, currency: "EUR", locale: Locale(identifier: "en_US")) }
        }
        rejects { _ = try ProjectHourlyRate.parse("3", currency: "INVALID") }
        let suite = "keep.project-rates.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.coderInvalidValue) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = TimesheetPersistence(defaults: defaults)
        let workspace = WorkspaceModel(persistence: persistence, calendar: calendar, date: now)
        let original = FocusProject.defaults[0]
        let project = try workspace.createProject(name: "Consulting", accent: .denim, hourlyRate: eur, at: clock, date: now)
        expect(try persistence.load().customProjects.first?.hourlyRate == eur, "Rate and currency persist immediately")
        rejects { _ = try workspace.createProject(name: "Duplicate color", accent: .denim) }
        rejects { _ = try workspace.createProject(name: "Reserved", accent: .habits) }
        rejects { try workspace.updateProject(project, name: project.name, accent: .sage) }
        try workspace.updateProject(project, name: project.name, accent: .denim, at: clock, date: now)
        expect(workspace.projects.first { $0.id == project.id }?.hourlyRate == eur, "Keeping a project's own color and editing its name preserves its rate")
        workspace.deleteProject(.habits, at: clock, date: now)
        expect(workspace.projects.contains(.habits), "Habits cannot be deleted")
        rejects { try workspace.updateProject(.habits, name: "Habits", accent: .teal) }
        rejects { try workspace.updateProject(project, name: project.name, accent: .denim, hourlyRate: .init(amount: -1, currency: "EUR")) }
        try workspace.updateProject(project, name: project.name, accent: .denim, hourlyRate: nil, at: clock, date: now)
        expect(try persistence.load().customProjects.first?.hourlyRate == nil, "Clearing the field removes the saved rate")
        try workspace.updateProject(project, name: project.name, accent: .denim, hourlyRate: eur, at: clock, date: now)
        for color in FocusProject.Accent.projectColors where !workspace.projects.contains(where: { $0.accent == color }) {
            _ = try workspace.createProject(name: "Project \(color.name)", accent: color, at: clock, date: now)
        }
        expect(workspace.projects.count == 31 && !workspace.canCreateProject, "Limit is thirty ordinary projects plus protected Habits")
        rejects { _ = try workspace.createProject(name: "Thirty-first", accent: .denim) }
        workspace.deleteProject(project, at: clock, date: now)
        expect(workspace.canCreateProject, "Deleting a project frees its color and slot")
        _ = try workspace.createProject(name: "Reused", accent: .denim, at: clock, date: now)
        expect(!workspace.canCreateProject, "A freed color can be reused once")

        var legacy = TimesheetLedger()
        let oldHabit = FocusProject(id: "legacy-habits", name: "Habits", accent: .terracotta, category: "Personal project")
        let duplicate = FocusProject(id: "duplicate", name: "Shared old color", accent: .sage, category: "Personal project")
        legacy.registerProject(oldHabit); legacy.registerProject(duplicate)
        legacy.record(project: oldHabit, from: now.addingTimeInterval(-3600), seconds: 1800, calendar: calendar, sessionID: UUID(), task: "Walk")
        legacy.record(project: duplicate, from: now.addingTimeInterval(-1800), seconds: 900, calendar: calendar, sessionID: UUID(), task: "Work")
        let migrated = WorkspaceModel(ledger: legacy, calendar: calendar, date: now)
        let habitsProject = migrated.projects.first { $0.id == oldHabit.id }
        expect(habitsProject?.accent == .habits && migrated.projects.filter(\.isHabitsProject).count == 1, "Legacy Habits retains identity with reserved color")
        expect(Set(migrated.projects.map(\.accent)).count == migrated.projects.count, "Legacy duplicate colors receive available unique colors")
        expect(migrated.ledger.sessions.map(\.id) == legacy.sessions.map(\.id) && migrated.ledger.sessions.map(\.seconds) == legacy.sessions.map(\.seconds), "Migration preserves recorded identities and time")
        if let habitsProject { migrated.deleteProject(habitsProject); expect(migrated.projects.contains(habitsProject), "Legacy Habits is protected too") }
        let migratedBytes = try JSONEncoder().encode(migrated.ledger)
        defaults.set(migratedBytes, forKey: persistence.key)
        let reopened = WorkspaceModel(persistence: persistence, calendar: calendar, date: now)
        expect(reopened.projects == migrated.projects, "Migrated project colors survive reload")

        var ledger = TimesheetLedger()
        ledger.registerProject(project)
        var dollarProject = FocusProject(id: "dollars", name: "Design", accent: .olive, category: "Work", hourlyRate: usd)
        ledger.registerProject(dollarProject)
        ledger.record(project: project, from: now.addingTimeInterval(-7200), seconds: 3600, calendar: calendar, sessionID: UUID(), task: "Research")
        ledger.record(project: project, from: now.addingTimeInterval(-3600), seconds: 1800, calendar: calendar, sessionID: UUID(), task: "Writing")
        ledger.record(project: dollarProject, from: now.addingTimeInterval(-1800), seconds: 1800, calendar: calendar, sessionID: UUID(), task: "Design")
        ledger.record(project: original, from: now.addingTimeInterval(-900), seconds: 900, calendar: calendar, sessionID: UUID(), task: "No rate")
        let statsWorkspace = WorkspaceModel(ledger: ledger, calendar: calendar, date: now)
        let cache = StatsCache()
        var cursor: (epoch: UUID, revision: UInt64)?
        func snapshot(_ query: StatsQuery = .init()) async throws -> StatsSnapshot {
            let batch = statsWorkspace.readIndex.batch(since: cursor?.revision, epoch: cursor?.epoch)
            let value = try await cache.snapshot(batch: batch, query: query, supplement: .init(taskRevision: 0, habitRevision: 0, tasks: [], habits: []), now: now, calendar: calendar)
            cursor = (batch.epoch, batch.revision)
            return value
        }
        func costs(_ query: StatsQuery = .init()) async throws -> [ProjectCost] {
            try await snapshot(query).projectCosts(projects: statsWorkspace.readIndex.statsProjects)
        }
        let all = try await costs()
        expect(all.count == 2 && all.first { $0.id == project.id }?.amount == eur.amount * Decimal(3) / 2, "Costs exclude projects without rates and use hours precisely")
        expect(Set(all.map { $0.rate.currency }) == ["EUR", "USD"], "Currencies remain distinct")
        var query = StatsQuery(); query.projectID = project.id; query.taskKeys = ["writing"]
        expect(try await costs(query).first?.amount == eur.amount / 2, "Task and project filters apply to estimated costs")
        query.taskKeys = ["missing"]
        expect(try await costs(query).isEmpty, "Empty filters produce no costs")
        query = StatsQuery(period: .custom, customStart: now.addingTimeInterval(-7 * 86400), customEnd: now.addingTimeInterval(-86400))
        expect(try await costs(query).isEmpty, "Dates filter costs")
        try statsWorkspace.updateProject(project, name: project.name, accent: .denim, hourlyRate: .init(amount: 120, currency: "EUR"), at: clock, date: now)
        expect(try await costs().first { $0.id == project.id }?.amount == 180, "Warm cache reflects changed current rates")
        statsWorkspace.deleteProject(project, at: clock, date: now)
        expect(try await costs().first { $0.id == project.id }?.amount == 180, "Deleted projects retain historical cost estimates")
        try statsWorkspace.updateProject(dollarProject, name: dollarProject.name, accent: .olive, hourlyRate: nil, at: clock, date: now)
        expect(try await costs().count == 1, "Removing a rate invalidates warm Stats metadata")
        dollarProject.hourlyRate = nil
        let encoded = try JSONEncoder().encode(payload(statsWorkspace.ledger))
        let decoded = try JSONDecoder().decode(KeepDataPayload.self, from: encoded)
        expect(decoded.workspace.customProjects.first { $0.id == project.id }?.hourlyRate?.amount == 120, "Data archives preserve rates")
        let review = try ImportMerge.review(source: decoded, local: payload(TimesheetLedger()), scope: .all, decisions: .init())
        expect(review.candidate.workspace.customProjects.first { $0.id == project.id }?.hourlyRate?.amount == 120, "Imports preserve rate metadata")
        var imported = payload(statsWorkspace.ledger)
        for i in 0..<31 { imported.workspace.customProjects.append(.init(id: "import-\(i)", name: "Imported \(i)", accent: .rose, category: "Work")) }
        let limitReview = try ImportMerge.review(source: imported, local: payload(TimesheetLedger()), scope: .all, decisions: .init())
        expect(limitReview.blockers.contains { $0.contains("30-project limit") }, "Imports cannot bypass the project cap")
        let settings = PortableSettings(SettingsArchive())
        let persistentSnapshot = PersistentSnapshot(workspace: statsWorkspace.ledger, tasks: .init(), habits: .init(), settings: settings, projects: statsWorkspace.readIndex.statsProjects, capturedAt: now, calendar: calendar)
        let export = try ExportReports.make(.init(data: .stats, from: now, through: now, projectID: nil, taskKeys: nil), snapshot: persistentSnapshot)
        expect(export.first { $0.filename == "project_costs.csv" }.map { String(decoding: $0.contents, as: UTF8.self).contains("EUR,120,5400.0,180") } == true, "Stats CSV includes current rates and filtered estimates")
        print("Passed \(checks) project color, protection, rate, cost, migration and archive checks")
    }
}
