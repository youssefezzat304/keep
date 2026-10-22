import Foundation

/// Preserve old untimed corrections while exposing the same project runs as Calendar.
struct TimesheetDayProjection {
    let blocks: [CalendarProjectBlock]
    let total: Double
    var recorded: Double { blocks.reduce(0) { $0 + $1.seconds } }
    var adjustment: Double { total - recorded }

    init(projectID: String, dayID: String, index: WorkspaceReadIndex) {
        _ = index.revision
        // Group the whole day first: another project must still interrupt a run.
        blocks = CalendarProjectBlock.grouping(index.sessions(on: dayID)).filter { $0.project.id == projectID }
        total = index.entries["\(projectID)/\(dayID)"]?.seconds ?? 0
    }
}
