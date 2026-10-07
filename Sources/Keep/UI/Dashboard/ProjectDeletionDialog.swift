import SwiftUI

struct ProjectDeletionDialog: View {
    let project: FocusProject
    let canDelete: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete project?").font(KeepTheme.headingFont(size: 27))
            Text("Remove \(project.name) from your project list?")
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("Recorded time stays in Timesheet and Calendar. If selected, running timers continue under No project.")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .keyboardShortcut(.cancelAction)
                Button("Delete project", role: .destructive) { onDelete(); dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(!canDelete)
            }
        }
        .padding(24).frame(width: 420)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
}
