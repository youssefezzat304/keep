import SwiftUI

struct HabitTaskExtensionField: View {
    @Bindable var editor: FocusTaskEditor
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        if let habit = editor.habit {
            VStack(alignment: .leading, spacing: 8) {
                Text(habit.name).font(.system(size: 15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Name extension (optional)").font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
                TextField("Name extension (optional)", text: $editor.nameExtension)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: isFocused ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                    .focused($isFocused)
                    .accessibilityLabel("Habit name extension, optional")
                    .help("Add a detail, such as the book you’re reading")
                    .onSubmit { if editor.canCommit { onSubmit() } }
                Text(editor.extendedTitle).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Task name: \(editor.extendedTitle)")
                if !editor.canCommit || editor.errorMessage != nil {
                    Text(editor.errorMessage ?? HabitTaskNameError.tooLong.localizedDescription)
                        .font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Save extension", action: onSubmit)
                    .buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(!editor.canCommit)
            }
            .onAppear { isFocused = true }
        }
    }
}
