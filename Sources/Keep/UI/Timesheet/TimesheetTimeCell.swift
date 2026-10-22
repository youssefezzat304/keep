import SwiftUI

struct TimesheetTimeCell: View {
    let seconds: TimeInterval
    let workspace: WorkspaceModel
    let project: FocusProject
    let day: TimesheetDay
    let color: Color
    let canEdit: Bool
    @State private var isEditing = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button { isEditing = true } label: {
            Text(seconds > 0 ? TimesheetDuration.clock(seconds) : "—")
                .font(.system(size: 13))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(seconds > 0 ? KeepTheme.ink : KeepTheme.mutedInk)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(seconds > 0 ? color.opacity(0.18) : KeepTheme.paper, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isFocused || isEditing ? KeepTheme.focusRing : isHovered ? KeepTheme.accentStrong : KeepTheme.controlBorder, lineWidth: isFocused || isEditing ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .focused($isFocused)
        .disabled(!canEdit)
        .accessibilityLabel("Edit \(project.name), \(day.label) \(day.number)")
        .accessibilityValue(seconds > 0 ? TimesheetDuration.clock(seconds) : "No time recorded")
        .help("View and edit the recorded Calendar blocks for this day")
        .sheet(isPresented: $isEditing) {
            TimesheetDaySessions(workspace: workspace, project: project, day: day)
        }
    }
}
