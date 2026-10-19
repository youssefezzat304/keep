import SwiftUI

struct HabitDeletionDialog: View {
    let habit: Habit
    let canDelete: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete habit?").font(KeepTheme.headingFont(size: 27))
            Text("Delete \(habit.name) and all its habit progress?")
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("This removes its check-ins, streaks and recurring task rows. This cannot be undone.")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.accentStrong)
                .fixedSize(horizontal: false, vertical: true)
            Text("Recorded focus time stays in Timesheet and Calendar. Running timers continue with the current task name.")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .keyboardShortcut(.cancelAction)
                Button("Delete habit", role: .destructive) { onDelete(); dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(!canDelete)
            }
        }
        .padding(24).frame(width: 420)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
}
