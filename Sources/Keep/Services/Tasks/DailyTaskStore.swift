import Foundation
import Observation

@Observable
final class DailyTaskStore {
    private(set) var archive: TaskArchive
    private(set) var persistenceError: String?
    private(set) var loadFailed = false
    var canEdit: Bool { !loadFailed }
    var habitPersistenceError: String? { habits?.persistenceError }
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
    @ObservationIgnored private let habits: HabitStore?

    init(archive: TaskArchive = TaskArchive(), persistence: TaskPersistence? = nil, calendar: Calendar = .autoupdatingCurrent, habits: HabitStore? = nil) {
        self.archive = archive
        self.persistence = persistence
        self.habits = habits
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

    func tasks(on dayID: String) -> [FocusTask] {
        let ordinary = archive.days[dayID] ?? []
        guard TaskDay.isValid(dayID), let habits, !habits.loadFailed else { return ordinary }
        let hidden = archive.hiddenHabitIDs[dayID, default: []]
        let scheduled = habits.habits.filter { $0.isScheduled(on: dayID) && !hidden.contains($0.id) }
        return ordinary + scheduled.map {
            FocusTask(id: $0.id, title: $0.name, isComplete: habits.isComplete($0, on: dayID), habitID: $0.id)
        }
    }

    func canStartTimers(on dayID: String, today: Date) -> Bool {
        TaskDay.isValid(dayID) && dayID == TaskDay.id(for: today, calendar: calendar)
    }

    func canComplete(_ task: FocusTask, on dayID: String, today: Date) -> Bool {
        canEdit && (task.habitID == nil || (habits?.canEdit == true && dayID <= TaskDay.id(for: today, calendar: calendar)))
    }

    @discardableResult
    func add(_ title: String, on dayID: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, TaskDay.isValid(dayID), !title.isEmpty else { return false }
        archive.days[dayID, default: []].append(FocusTask(title: title))
        save()
        return true
    }

    func setComplete(_ complete: Bool, taskID: UUID, on dayID: String, habitID: UUID? = nil, today: Date = .now) {
        if let habitID {
            guard canEdit, taskID == habitID, let habits, let habit = habits.habits.first(where: { $0.id == habitID }),
                  !archive.hiddenHabitIDs[dayID, default: []].contains(habitID) else { return }
            _ = habits.setAmount(complete ? habit.goal.target : 0, habitID: habitID, on: dayID, today: today)
            return
        }
        guard canEdit, var tasks = archive.days[dayID], let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isComplete = complete
        archive.days[dayID] = tasks
        save()
    }

    func remove(taskID: UUID, on dayID: String, habitID: UUID? = nil) {
        if let habitID {
            guard canEdit, taskID == habitID, TaskDay.isValid(dayID),
                  let habits, !habits.loadFailed, habits.habits.contains(where: { $0.id == habitID && $0.isScheduled(on: dayID) }) else { return }
            archive.hiddenHabitIDs[dayID, default: []].insert(habitID)
            save()
            return
        }
        guard canEdit, var tasks = archive.days[dayID], tasks.contains(where: { $0.id == taskID }) else { return }
        tasks.removeAll { $0.id == taskID }
        if tasks.isEmpty { archive.days.removeValue(forKey: dayID) }
        else { archive.days[dayID] = tasks }
        save()
    }

    func retryPersistence() {
        habits?.retryPersistence()
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
