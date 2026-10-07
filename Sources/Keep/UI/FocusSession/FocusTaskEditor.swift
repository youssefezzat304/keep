import Foundation
import Observation

/// Window-local editing state; timer actions commit once before settling/starting time.
@Observable
final class FocusTaskEditor {
    var text = ""
    private(set) var isEditing = false

    func begin(in workspace: WorkspaceModel) {
        text = workspace.taskName
        isEditing = true
    }

    func commit(to workspace: WorkspaceModel) {
        guard isEditing else { return }
        workspace.setTaskName(text.trimmingCharacters(in: .whitespacesAndNewlines))
        isEditing = false
    }

    func cancel() { isEditing = false }
}
