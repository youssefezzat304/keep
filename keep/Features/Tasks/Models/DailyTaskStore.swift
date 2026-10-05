import Foundation
import Observation

@Observable
final class DailyTaskStore {
    private(set) var archive: TaskArchive
    private(set) var persistenceError: String?
    private(set) var loadFailed = false
    var canEdit: Bool { !loadFailed }
    @ObservationIgnored private let calendarSource: Calendar
    var calendar: Calendar {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendarSource.timeZone
        local.locale = calendarSource.locale
        local.firstWeekday = calendarSource.firstWeekday
        return local
    }
    @ObservationIgnored private let persistence: TaskPersistence?
    @ObservationIgnored private var needsSave = false

    init(archive: TaskArchive = TaskArchive(), persistence: TaskPersistence? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.archive = archive
        self.persistence = persistence
        // One Gregorian civil-date scheme for keys, picker, navigation, and local storage.
        calendarSource = calendar
        if let persistence {
            do { self.archive = try persistence.load() }
            catch {
                loadFailed = true
                persistenceError = "Couldn’t load your saved tasks. Retry before changing them."
            }
        }
    }

    func tasks(on dayID: String) -> [FocusTask] { archive.days[dayID] ?? [] }

    @discardableResult
    func add(_ title: String, on dayID: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, TaskDay.isValid(dayID), !title.isEmpty else { return false }
        archive.days[dayID, default: []].append(FocusTask(title: title))
        save()
        return true
    }

    func setComplete(_ complete: Bool, taskID: UUID, on dayID: String) {
        guard canEdit, var tasks = archive.days[dayID], let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isComplete = complete
        archive.days[dayID] = tasks
        save()
    }

    func remove(taskID: UUID, on dayID: String) {
        guard canEdit, var tasks = archive.days[dayID], tasks.contains(where: { $0.id == taskID }) else { return }
        tasks.removeAll { $0.id == taskID }
        if tasks.isEmpty { archive.days.removeValue(forKey: dayID) }
        else { archive.days[dayID] = tasks }
        save()
    }

    func retryPersistence() {
        if loadFailed, let persistence {
            do {
                archive = try persistence.load()
                loadFailed = false
                persistenceError = nil
            } catch { persistenceError = "Couldn’t load your saved tasks. Retry before changing them." }
        } else if needsSave { save() }
    }

    private func save() {
        guard let persistence else { return }
        needsSave = true
        do {
            try persistence.save(archive)
            needsSave = false
            persistenceError = nil
        } catch { persistenceError = "Couldn’t save your tasks. Your changes are still here; retry saving." }
    }
}
