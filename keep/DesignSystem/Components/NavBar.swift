import SwiftUI

struct NavBar: View {
    let isTimesheetSelected: Bool
    let onSelectFocus: () -> Void
    let onSelectTimesheet: () -> Void
    @FocusState private var focusedTab: String?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("keep")
                    .font(.system(size: 28, weight: .medium, design: .serif))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            tab("Focus", symbol: "sun.max", isSelected: !isTimesheetSelected, action: onSelectFocus)
            tab("Timesheet", symbol: "calendar", isSelected: isTimesheetSelected, action: onSelectTimesheet)
            futureDestination("Stats", symbol: "chart.bar")
            futureDestination("Settings", symbol: "slider.horizontal.3")
        }
        .foregroundStyle(KeepTheme.ink)
    }

    private func tab(_ title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? KeepTheme.mutedWarm : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focused($focusedTab, equals: title)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focusedTab == title ? KeepTheme.focusRing : .clear, lineWidth: 2)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func futureDestination(_ title: String, symbol: String) -> some View {
        Button {} label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(KeepTheme.mutedInk)
        .disabled(true)
        .help("\(title) will be available later")
    }
}

#Preview {
    NavBar(isTimesheetSelected: true, onSelectFocus: {}, onSelectTimesheet: {})
        .padding().background(KeepTheme.paper)
}
