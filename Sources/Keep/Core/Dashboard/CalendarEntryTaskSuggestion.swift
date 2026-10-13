import Foundation

nonisolated struct CalendarEntryTaskSuggestion: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let reference: TaskReference?

    static func matching(_ query: String, in suggestions: [Self]) -> [Self] {
        let query = StatsQuery.taskKey(query)
        guard !query.isEmpty else { return suggestions }
        func rank(_ title: String) -> Int {
            let name = StatsQuery.taskKey(title)
            return name == query ? 0 : name.hasPrefix(query) ? 1 : 2
        }
        return suggestions.enumerated().filter { StatsQuery.taskKey($0.element.title).contains(query) }
            .sorted { rank($0.element.title) == rank($1.element.title) ? $0.offset < $1.offset : rank($0.element.title) < rank($1.element.title) }
            .map(\.element)
    }
}
