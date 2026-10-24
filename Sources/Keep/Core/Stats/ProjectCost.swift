import Foundation

nonisolated struct ProjectCost: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let rate: ProjectHourlyRate
    let seconds: Double
    var amount: Decimal { Decimal(seconds) / 3600 * rate.amount }
}

extension StatsSnapshot {
    /// Buckets already honor the selected dates, project, task filters and live cutoff.
    nonisolated func projectCosts(projects: [StatsInput.Project]) -> [ProjectCost] {
        var seconds: [String: Double] = [:]
        for bucket in buckets {
            for project in bucket.projects { seconds[project.id, default: 0] += project.seconds }
        }
        return projects.compactMap { project in
            guard let rate = project.hourlyRate, rate.isValid, let time = seconds[project.id], time > 0 else { return nil }
            return ProjectCost(id: project.id, name: project.name + (project.deleted ? " (Deleted)" : ""), rate: rate, seconds: time)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
