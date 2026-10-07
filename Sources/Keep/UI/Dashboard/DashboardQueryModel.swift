import Foundation
import Observation

@Observable final class DashboardQueryModel {
    private(set) var projection = WeeklyProjection()
    @ObservationIgnored private var cache: [Entry] = []
    @ObservationIgnored private(set) var preparations = 0
    var cachedWeekCount: Int { cache.count }
    private struct Entry {
        let days: [String]
        let epoch: UUID
        let revisions: [UInt64]
        let metadataRevision: UInt64
        let locale: String
        let projection: WeeklyProjection
    }
    func refresh(week: TimesheetWeek, index: WorkspaceReadIndex, calendar: Calendar) {
        let days = week.dayIDs, revisions = days.map { index.revision(on: $0) }
        let locale = calendar.locale?.identifier ?? Locale.current.identifier
        if let position = cache.firstIndex(where: { $0.days == days && $0.epoch == index.epoch && $0.revisions == revisions && $0.metadataRevision == index.catalogRevision && $0.locale == locale }) {
            let value = cache.remove(at: position); cache.append(value); projection = value.projection
            return
        }
        cache.removeAll { $0.days == days }
        projection = WeeklyProjection(days: days, index: index); preparations += 1
        cache.append(Entry(days: days, epoch: index.epoch, revisions: revisions, metadataRevision: index.catalogRevision, locale: locale, projection: projection))
        if cache.count > 8 { cache.removeFirst(cache.count - 8) }
    }
}
