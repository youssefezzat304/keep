import SwiftUI

struct NavBar: View {
    let selection: WorkspaceTab
    let onSelectFocus: () -> Void
    let onSelectDashboard: () -> Void
    let onSelectHabits: () -> Void
    let onSelectStats: () -> Void
    var isCompact = false
    let onSelectSettings: () -> Void
    @FocusState private var focusedTab: String?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("keep")
                    .font(KeepTheme.headingFont(size: 28, weight: .medium))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            tab("Focus", symbol: "sun.max", isSelected: selection == .focus, action: onSelectFocus)
            tab("Dashboard", symbol: "square.grid.2x2", isSelected: selection == .dashboard, action: onSelectDashboard)
            tab("Habit tracker", symbol: "repeat", isSelected: selection == .habits, action: onSelectHabits)
            tab("Stats", symbol: "chart.bar", isSelected: selection == .stats, action: onSelectStats)
            tab("Settings", symbol: "slider.horizontal.3", isSelected: selection == .settings, action: onSelectSettings)
        }
        .foregroundStyle(KeepTheme.ink)
    }

    @ViewBuilder private func navigationLabel(_ title: String, symbol: String) -> some View {
        if isCompact { Image(systemName: symbol).font(.system(size: 16)).frame(width: 18) }
        else { Label(title, systemImage: symbol).fixedSize() }
    }

    private func tab(_ title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            navigationLabel(title, symbol: symbol)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .padding(.horizontal, isCompact ? 12 : 14)
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
        .accessibilityLabel(title)
        .help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}

#Preview {
    NavBar(selection: .dashboard, onSelectFocus: {}, onSelectDashboard: {}, onSelectHabits: {}, onSelectStats: {}, onSelectSettings: {})
        .padding().background(KeepTheme.paper)
}
