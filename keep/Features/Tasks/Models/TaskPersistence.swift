import Foundation

struct TaskArchive: Codable, Equatable {
    var days: [String: [FocusTask]] = [:]
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
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted
            }) else { throw CocoaError(.coderReadCorrupt) }
        }
        return archive
    }

    func save(_ archive: TaskArchive) throws {
        defaults.set(try JSONEncoder().encode(archive), forKey: key)
    }
}
