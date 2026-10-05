import SwiftUI

enum WorkspaceTab {
    case focus
    case timesheet
}

struct AppShellView: View {
    @State private var selectedTab: WorkspaceTab

    init(initialTab: WorkspaceTab = .focus) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    NavBar(
                        isTimesheetSelected: selectedTab == .timesheet,
                        onSelectFocus: { selectedTab = .focus },
                        onSelectTimesheet: { selectedTab = .timesheet }
                    )

                    // Keep the focus view mounted so changing tabs preserves its local state.
                    ZStack(alignment: .top) {
                        FocusSessionView(isCompact: geometry.size.width < 820)
                            .frame(height: selectedTab == .focus ? nil : 0, alignment: .top)
                            .clipped()
                            .opacity(selectedTab == .focus ? 1 : 0)
                            .allowsHitTesting(selectedTab == .focus)
                            .accessibilityHidden(selectedTab != .focus)

                        TimesheetView()
                            .frame(height: selectedTab == .timesheet ? nil : 0, alignment: .top)
                            .clipped()
                            .opacity(selectedTab == .timesheet ? 1 : 0)
                            .allowsHitTesting(selectedTab == .timesheet)
                            .accessibilityHidden(selectedTab != .timesheet)
                    }
                }
                .padding(24)
                .frame(maxWidth: 1100)
                .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(KeepTheme.border.opacity(0.5), lineWidth: 1)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(KeepTheme.background)
        }
        .frame(minWidth: 680, minHeight: 650)
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .preferredColorScheme(.light)
    }
}

#Preview("Focus") {
    AppShellView().frame(width: 1000, height: 900)
}

#Preview("Timesheet") {
    AppShellView(initialTab: .timesheet).frame(width: 1000, height: 900)
}
