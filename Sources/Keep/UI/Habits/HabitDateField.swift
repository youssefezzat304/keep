import SwiftUI

/// Reuses Keep's task calendar instead of the platform's compact date stepper.
struct HabitDateField: View {
    let label: String
    @Binding var date: Date
    let calendar: Calendar
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(KeepTheme.accentStrong)
                Text(HabitDates.label(date, calendar: calendar, style: .dateTime.day().month(.abbreviated).year()))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(KeepTheme.mutedInk)
            }
        }
        .buttonStyle(KeepButtonStyle())
        .accessibilityLabel(label).accessibilityValue(TaskDay.id(for: date, calendar: calendar))
        .popover(isPresented: $presented) {
            TaskDatePicker(date: date, calendar: calendar, confirmationTitle: "Choose date") { selected in
                date = selected
                presented = false
            }
        }
    }
}
