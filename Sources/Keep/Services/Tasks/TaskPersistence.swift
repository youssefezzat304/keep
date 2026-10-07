import Foundation

struct TaskArchive: Codable, Equatable {
    var days: [String: [FocusTask]] = [:]
    var hiddenHabitIDs: [String: Set<UUID>] = [:]
    init(days: [String: [FocusTask]] = [:], hiddenHabitIDs: [String: Set<UUID>] = [:]) {
        self.days = days
        self.hiddenHabitIDs = hiddenHabitIDs
    }
    private enum CodingKeys: String, CodingKey { case days, hiddenHabitIDs }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        days = try values.decode([String: [FocusTask]].self, forKey: .days)
        hiddenHabitIDs = try values.decodeIfPresent([String: Set<UUID>].self, forKey: .hiddenHabitIDs) ?? [:]
    }
}

struct TaskPersistence {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "keep.tasks.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> TaskArchive {
        guard defaults.object(forKey: key) != nil else { return TaskArchive() }
        guard let data = defaults.data(forKey: key) else { throw CocoaError(.coderReadCorrupt) }
        let archive = try JSONDecoder().decode(TaskArchive.self, from: data)
        for (day, tasks) in archive.days {
            var seen = Set<UUID>()
            guard TaskDay.isValid(day), tasks.allSatisfy({
                $0.habitID == nil && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted
            }) else { throw CocoaError(.coderReadCorrupt) }
        }
        guard archive.hiddenHabitIDs.keys.allSatisfy({ TaskDay.isValid($0) }) else { throw CocoaError(.coderReadCorrupt) }
        return archive
    }

    func save(_ archive: TaskArchive) throws {
        defaults.set(try JSONEncoder().encode(archive), forKey: key)
    }
}
