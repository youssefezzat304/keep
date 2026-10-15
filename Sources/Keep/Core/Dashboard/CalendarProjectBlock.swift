import Foundation

/// A visual run of one project's entries. Its gaps never become recorded time.
struct CalendarProjectBlock: Identifiable {
    let id: String
    let project: FocusProject
    var sessions: [RecordedSession]
    var startMinute: Double { sessions.map(\.startMinute).min() ?? 0 }
    var endMinute: Double { sessions.map(\.endMinute).max() ?? startMinute }
    var seconds: Double { sessions.reduce(0) { $0 + $1.seconds } }
    var startTime: String { sessions.first?.startTime ?? "" }
    var endTime: String { sessions.max { $0.endMinute < $1.endMinute }?.editableEndTime ?? "" }
    var titles: [String] {
        var seen: Set<String> = []
        return sessions.map(\.title).filter { seen.insert($0).inserted }
    }
    var gaps: [Range<Double>] {
        var end = startMinute, result: [Range<Double>] = []
        for session in sessions {
            if session.startMinute > end { result.append(end..<session.startMinute) }
            end = max(end, session.endMinute)
        }
        return result
    }

    static func grouping(_ sessions: [RecordedSession]) -> [CalendarProjectBlock] {
        let ordered = sessions.sorted {
            if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
        var blocks: [CalendarProjectBlock] = []
        for session in ordered {
            if let last = blocks.last, last.project.id == session.project.id,
               last.sessions.first?.dayID == session.dayID,
               last.sessions.first?.timeZoneID == session.timeZoneID {
                blocks[blocks.count - 1].sessions.append(session)
            } else {
                blocks.append(.init(id: session.id, project: session.project, sessions: [session]))
            }
        }
        return blocks
    }

    struct Placement: Identifiable {
        let block: CalendarProjectBlock
        let lane: Int
        let laneCount: Int
        var id: String { block.id }
    }
    static func placements(_ blocks: [CalendarProjectBlock], hourHeight: Double) -> [Placement] {
        var ends: [Double] = []
        var result: [Placement] = [], cluster: [(CalendarProjectBlock, Int)] = []
        func finishCluster() {
            result.append(contentsOf: cluster.map { .init(block: $0.0, lane: $0.1, laneCount: max(1, ends.count)) })
            cluster = []; ends = []
        }
        for block in blocks {
            if let lastEnd = ends.max(), block.startMinute >= lastEnd { finishCluster() }
            let lane = ends.firstIndex { $0 <= block.startMinute } ?? ends.count
            let end = max(block.endMinute, block.startMinute + 34 / hourHeight * 60)
            if lane == ends.count { ends.append(end) } else { ends[lane] = end }
            cluster.append((block, lane))
        }
        finishCluster()
        return result
    }
}
