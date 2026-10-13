import Foundation
import Observation

/// Window-local editing state; timer actions commit once before settling/starting time.
@Observable
final class FocusTaskEditor {
    var text = ""
    var nameExtension = ""
    private(set) var isEditing = false
    private(set) var habit: Habit?
    private(set) var errorMessage: String?
    private var initialText = ""

    var editsHabitExtension: Bool { habit != nil && text == initialText }
    var extendedTitle: String { HabitTaskName.title(habit?.name ?? "", extension: nameExtension) }
    var canCommit: Bool { !editsHabitExtension || extendedTitle.count <= 200 }

    func begin(in workspace: WorkspaceModel) {
        text = workspace.activeTaskName
        initialText = text
        habit = workspace.activeHabit
        nameExtension = workspace.habitNameExtension ?? ""
        errorMessage = nil
        isEditing = true
    }

    @discardableResult
    func commit(to workspace: WorkspaceModel) -> Bool {
        guard isEditing else { return true }
        guard canCommit else { errorMessage = HabitTaskNameError.tooLong.localizedDescription; return false }
        if editsHabitExtension, let habit {
            do { try workspace.setHabitNameExtension(nameExtension, habitID: habit.id) }
            catch { errorMessage = error.localizedDescription; return false }
        } else {
            workspace.setTaskName(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        isEditing = false
        return true
    }

    func cancel() { isEditing = false }
}
