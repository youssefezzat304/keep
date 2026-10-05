import SwiftUI

struct TimesheetTimeCell: View {
    let seconds: TimeInterval
    let projectName: String
    let day: TimesheetDay
    let color: Color
    let canEdit: Bool
    let onSave: (TimeInterval) -> Void
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
        .accessibilityLabel("Edit \(projectName), \(day.label) \(day.number)")
        .accessibilityValue(seconds > 0 ? TimesheetDuration.clock(seconds) : "No time recorded")
        .help("Edit time in hours, minutes, and seconds")
        .popover(isPresented: $isEditing) {
            TimesheetEntryEditor(projectName: projectName, day: day, seconds: seconds) { value in
                onSave(value)
                isEditing = false
            } onCancel: { isEditing = false }
        }
    }
}

struct TimesheetEntryEditor: View {
    let projectName: String
    let day: TimesheetDay
    let onSave: (TimeInterval) -> Void
    let onCancel: () -> Void
    @State private var draft: String
    @State private var showsError = false
    @FocusState private var isFocused: Bool

    init(projectName: String, day: TimesheetDay, seconds: TimeInterval, onSave: @escaping (TimeInterval) -> Void, onCancel: @escaping () -> Void) {
        self.projectName = projectName
        self.day = day
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: TimesheetDuration.clock(seconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(projectName).font(.system(size: 19, design: .serif))
            Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 12))
                .foregroundStyle(KeepTheme.mutedInk)

            TextField("Duration", text: $draft)
                .font(.system(size: 18).monospacedDigit())
                .textFieldStyle(.plain)
                .padding(12)
                .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: isFocused ? 2 : 1)
                }
                .focused($isFocused)
                .onSubmit(save)
                .accessibilityLabel("Duration in hours, minutes, and optional seconds")

            Text(showsError ? "Use h:mm or h:mm:ss, with minutes and seconds from 00 to 59." : "Use h:mm or h:mm:ss. Leave blank to clear.")
                .font(.system(size: 12))
                .foregroundStyle(showsError ? KeepTheme.accentStrong : KeepTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.paper)
        .onAppear { isFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private func save() {
        guard let seconds = TimesheetDuration.parse(draft) else {
            showsError = true
            isFocused = true
            return
        }
        onSave(seconds)
    }
}
